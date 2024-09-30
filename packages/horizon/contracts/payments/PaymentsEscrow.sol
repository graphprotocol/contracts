// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../interfaces/IPaymentsEscrow.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";

import { GraphDirectory } from "../utilities/GraphDirectory.sol";

/**
 * @title PaymentsEscrow contract
 * @dev Implements the {IPaymentsEscrow} interface
 * @notice This contract is part of the Graph Horizon payments protocol. It holds the funds (GRT)
 * for payments made through the payments protocol for services provided
 * via a Graph Horizon data service.
 */
contract PaymentsEscrow is Initializable, MulticallUpgradeable, GraphDirectory, IPaymentsEscrow {
    using TokenUtils for IGraphToken;

    /// @notice Authorization details for payer-collector pairs
    mapping(address payer => mapping(address collector => IPaymentsEscrow.Collector collectorDetails))
        public authorizedCollectors;

    /// @notice Escrow account details for payer-receiver pairs
    mapping(address payer => mapping(address receiver => IPaymentsEscrow.EscrowAccount escrowAccount))
        public escrowAccounts;

    /// @notice The maximum thawing period (in seconds) for both escrow withdrawal and signer revocation
    /// @dev This is a precautionary measure to avoid inadvertedly locking funds for too long
    uint256 public constant MAX_THAWING_PERIOD = 90 days;

    /// @notice Thawing period in seconds for authorized collectors
    uint256 public immutable REVOKE_COLLECTOR_THAWING_PERIOD;

    /// @notice Thawing period in seconds for escrow funds withdrawal
    uint256 public immutable WITHDRAW_ESCROW_THAWING_PERIOD;

    modifier notPaused() {
        require(!_graphController().paused(), PaymentsEscrowIsPaused());
        _;
    }

    /**
     * @notice Construct the PaymentsEscrow contract
     * @param controller The address of the controller
     * @param revokeCollectorThawingPeriod Thawing period in seconds for authorized collectors
     * @param withdrawEscrowThawingPeriod Thawing period in seconds for escrow funds withdrawal
     */
    constructor(
        address controller,
        uint256 revokeCollectorThawingPeriod,
        uint256 withdrawEscrowThawingPeriod
    ) GraphDirectory(controller) {
        require(
            revokeCollectorThawingPeriod <= MAX_THAWING_PERIOD,
            PaymentsEscrowThawingPeriodTooLong(revokeCollectorThawingPeriod, MAX_THAWING_PERIOD)
        );
        require(
            withdrawEscrowThawingPeriod <= MAX_THAWING_PERIOD,
            PaymentsEscrowThawingPeriodTooLong(withdrawEscrowThawingPeriod, MAX_THAWING_PERIOD)
        );

        REVOKE_COLLECTOR_THAWING_PERIOD = revokeCollectorThawingPeriod;
        WITHDRAW_ESCROW_THAWING_PERIOD = withdrawEscrowThawingPeriod;
    }

    /**
     * @notice Initialize the contract
     */
    function initialize() external initializer {
        __Multicall_init();
    }

    /**
     * @notice See {IPaymentsEscrow-approveCollector}
     */
    function approveCollector(address collector_, uint256 allowance) external override notPaused {
        require(allowance != 0, PaymentsEscrowInvalidZeroTokens());
        Collector storage collector = authorizedCollectors[msg.sender][collector_];
        collector.allowance += allowance;
        emit AuthorizedCollector(msg.sender, collector_, allowance, collector.allowance);
    }

    /**
     * @notice See {IPaymentsEscrow-thawCollector}
     */
    function thawCollector(address collector) external override notPaused {
        authorizedCollectors[msg.sender][collector].thawEndTimestamp =
            block.timestamp +
            REVOKE_COLLECTOR_THAWING_PERIOD;
        emit ThawCollector(msg.sender, collector);
    }

    /**
     * @notice See {IPaymentsEscrow-cancelThawCollector}
     */
    function cancelThawCollector(address collector) external override notPaused {
        require(authorizedCollectors[msg.sender][collector].thawEndTimestamp != 0, PaymentsEscrowNotThawing());

        authorizedCollectors[msg.sender][collector].thawEndTimestamp = 0;
        emit CancelThawCollector(msg.sender, collector);
    }

    /**
     * @notice See {IPaymentsEscrow-revokeCollector}
     */
    function revokeCollector(address collector_) external override notPaused {
        Collector storage collector = authorizedCollectors[msg.sender][collector_];

        require(collector.thawEndTimestamp != 0, PaymentsEscrowNotThawing());
        require(
            collector.thawEndTimestamp < block.timestamp,
            PaymentsEscrowStillThawing(block.timestamp, collector.thawEndTimestamp)
        );

        delete authorizedCollectors[msg.sender][collector_];
        emit RevokeCollector(msg.sender, collector_);
    }

    /**
     * @notice See {IPaymentsEscrow-deposit}
     */
    function deposit(address receiver, uint256 tokens) external override notPaused {
        _deposit(msg.sender, receiver, tokens);
    }

    /**
     * @notice See {IPaymentsEscrow-depositTo}
     */
    function depositTo(address payer, address receiver, uint256 tokens) external override notPaused {
        _deposit(payer, receiver, tokens);
    }

    /**
     * @notice See {IPaymentsEscrow-thaw}
     */
    function thaw(address receiver, uint256 tokens) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][receiver];

        // if amount thawing is zero and requested amount is zero this is an invalid request.
        // otherwise if amount thawing is greater than zero and requested amount is zero this
        // is a cancel thaw request.
        if (tokens == 0) {
            require(account.tokensThawing != 0, PaymentsEscrowNotThawing());
            account.tokensThawing = 0;
            account.thawEndTimestamp = 0;
            emit CancelThaw(msg.sender, receiver);
            return;
        }

        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        account.tokensThawing = tokens;
        account.thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        emit Thaw(msg.sender, receiver, tokens, account.thawEndTimestamp);
    }

    /**
     * @notice See {IPaymentsEscrow-withdraw}
     */
    function withdraw(address receiver) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][receiver];
        require(account.thawEndTimestamp != 0, PaymentsEscrowNotThawing());
        require(
            account.thawEndTimestamp < block.timestamp,
            PaymentsEscrowStillThawing(block.timestamp, account.thawEndTimestamp)
        );

        // Amount is the minimum between the amount being thawed and the actual balance
        uint256 tokens = account.tokensThawing > account.balance ? account.balance : account.tokensThawing;

        account.balance -= tokens;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;
        _graphToken().pushTokens(msg.sender, tokens);
        emit Withdraw(msg.sender, receiver, tokens);
    }

    /**
     * @notice See {IPaymentsEscrow-collect}
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external override notPaused {
        // Check if collector is authorized and has enough funds
        Collector storage collector = authorizedCollectors[payer][msg.sender];
        require(collector.allowance >= tokens, PaymentsEscrowInsufficientAllowance(collector.allowance, tokens));

        // Check if there are enough funds in the escrow account
        EscrowAccount storage account = escrowAccounts[payer][receiver];
        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        // Reduce amount from approved collector and account balance
        collector.allowance -= tokens;
        account.balance -= tokens;

        uint256 balanceBefore = _graphToken().balanceOf(address(this));

        _graphToken().approve(address(_graphPayments()), tokens);
        _graphPayments().collect(paymentType, receiver, tokens, dataService, tokensDataService);

        uint256 balanceAfter = _graphToken().balanceOf(address(this));
        require(
            balanceBefore == tokens + balanceAfter,
            PaymentsEscrowInconsistentCollection(balanceBefore, balanceAfter, tokens)
        );

        emit EscrowCollected(payer, receiver, tokens);
    }

    /**
     * @notice See {IPaymentsEscrow-getBalance}
     */
    function getBalance(address payer, address receiver) external view override returns (uint256) {
        EscrowAccount storage account = escrowAccounts[payer][receiver];
        return account.balance - account.tokensThawing;
    }

    /**
     * @notice See {IPaymentsEscrow-deposit}
     * @param _payer The address of the payer
     * @param _receiver The address of the receiver
     * @param _tokens The amount of tokens to deposit
     */
    function _deposit(address _payer, address _receiver, uint256 _tokens) internal {
        escrowAccounts[_payer][_receiver].balance += _tokens;
        _graphToken().pullTokens(msg.sender, _tokens);
        emit Deposit(_payer, _receiver, _tokens);
    }
}
