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
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract PaymentsEscrow is Initializable, MulticallUpgradeable, GraphDirectory, IPaymentsEscrow {
    using TokenUtils for IGraphToken;

    /// @notice The maximum thawing period (in seconds) for both escrow withdrawal and collector revocation
    /// @dev This is a precautionary measure to avoid inadvertedly locking funds for too long
    uint256 public constant MAX_WAIT_PERIOD = 90 days;

    /// @notice Thawing period in seconds for escrow funds withdrawal
    uint256 public immutable WITHDRAW_ESCROW_THAWING_PERIOD;

    /// @notice Escrow account details for payer-collector-receiver tuples
    mapping(address payer => mapping(address collector => mapping(address receiver => IPaymentsEscrow.EscrowAccount escrowAccount)))
        public escrowAccounts;

    /**
     * @notice Modifier to prevent function execution when contract is paused
     * @dev Reverts if the controller indicates the contract is paused
     */
    modifier notPaused() {
        require(!_graphController().paused(), PaymentsEscrowIsPaused());
        _;
    }

    /**
     * @notice Construct the PaymentsEscrow contract
     * @param controller The address of the controller
     * @param withdrawEscrowThawingPeriod Thawing period in seconds for escrow funds withdrawal
     */
    constructor(address controller, uint256 withdrawEscrowThawingPeriod) GraphDirectory(controller) {
        require(
            withdrawEscrowThawingPeriod <= MAX_WAIT_PERIOD,
            PaymentsEscrowThawingPeriodTooLong(withdrawEscrowThawingPeriod, MAX_WAIT_PERIOD)
        );

        WITHDRAW_ESCROW_THAWING_PERIOD = withdrawEscrowThawingPeriod;
        _disableInitializers();
    }

    /// @inheritdoc IPaymentsEscrow
    function initialize() external initializer {
        __Multicall_init();
    }

    /// @inheritdoc IPaymentsEscrow
    function deposit(address collector, address receiver, uint256 tokens) external override notPaused {
        _deposit(msg.sender, collector, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function depositTo(address payer, address collector, address receiver, uint256 tokens) external override notPaused {
        _deposit(payer, collector, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function thaw(address collector, address receiver, uint256 tokens) external override notPaused {
        require(tokens > 0, PaymentsEscrowInvalidZeroTokens());

        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        account.tokensThawing = tokens;
        account.thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        emit Thaw(msg.sender, collector, receiver, tokens, account.thawEndTimestamp);
    }

    /// @inheritdoc IPaymentsEscrow
    function cancelThaw(address collector, address receiver) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
        require(account.tokensThawing != 0, PaymentsEscrowNotThawing());

        uint256 tokensThawing = account.tokensThawing;
        uint256 thawEndTimestamp = account.thawEndTimestamp;
        account.tokensThawing = 0;
        account.thawEndTimestamp = 0;

        emit CancelThaw(msg.sender, collector, receiver, tokensThawing, thawEndTimestamp);
    }

    /// @inheritdoc IPaymentsEscrow
    function withdraw(address collector, address receiver) external override notPaused {
        EscrowAccount storage account = escrowAccounts[msg.sender][collector][receiver];
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
        emit Withdraw(msg.sender, collector, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut
    ) external override notPaused {
        // Check if there are enough funds in the escrow account
        EscrowAccount storage account = escrowAccounts[payer][msg.sender][receiver];
        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        // Reduce amount from account balance
        account.balance -= tokens;

        uint256 escrowBalanceBefore = _graphToken().balanceOf(address(this));

        _graphToken().approve(address(_graphPayments()), tokens);
        _graphPayments().collect(paymentType, receiver, tokens, dataService, dataServiceCut);

        // Verify that the escrow balance is consistent with the collected tokens
        uint256 escrowBalanceAfter = _graphToken().balanceOf(address(this));
        require(
            escrowBalanceBefore == tokens + escrowBalanceAfter,
            PaymentsEscrowInconsistentCollection(escrowBalanceBefore, escrowBalanceAfter, tokens)
        );

        emit EscrowCollected(paymentType, payer, msg.sender, receiver, tokens);
    }

    /// @inheritdoc IPaymentsEscrow
    function getBalance(address payer, address collector, address receiver) external view override returns (uint256) {
        EscrowAccount storage account = escrowAccounts[payer][collector][receiver];
        return account.balance > account.tokensThawing ? account.balance - account.tokensThawing : 0;
    }

    /**
     * @notice Deposits funds into the escrow for a payer-collector-receiver tuple, where
     * the payer is the transaction caller.
     * @param _payer The address of the payer
     * @param _collector The address of the collector
     * @param _receiver The address of the receiver
     * @param _tokens The amount of tokens to deposit
     */
    function _deposit(address _payer, address _collector, address _receiver, uint256 _tokens) private {
        escrowAccounts[_payer][_collector][_receiver].balance += _tokens;
        _graphToken().pullTokens(msg.sender, _tokens);
        emit Deposit(_payer, _collector, _receiver, _tokens);
    }
}
