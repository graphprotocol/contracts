// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

// solhint-disable gas-strict-inequalities

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";

import { GraphDirectory } from "../utilities/GraphDirectory.sol";

/**
 * @title PaymentsEscrow contract
 * @author Edge & Node
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
        private _escrowAccounts;

    // forge-lint: disable-next-item(unwrapped-modifier-logic)
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
    function thaw(
        address collector,
        address receiver,
        uint256 tokens
    ) external override notPaused returns (uint256 tokensThawing) {
        return _thaw(collector, receiver, tokens, true);
    }

    /// @inheritdoc IPaymentsEscrow
    function thaw(
        address collector,
        address receiver,
        uint256 tokens,
        bool evenIfTimerReset
    ) external override notPaused returns (uint256 tokensThawing) {
        return _thaw(collector, receiver, tokens, evenIfTimerReset);
    }

    /// @inheritdoc IPaymentsEscrow
    function cancelThaw(
        address collector,
        address receiver
    ) external override notPaused returns (uint256 tokensThawing) {
        return _thaw(collector, receiver, 0, true);
    }

    /// @inheritdoc IPaymentsEscrow
    function withdraw(address collector, address receiver) external override notPaused returns (uint256 tokens) {
        EscrowAccount storage account = _escrowAccounts[msg.sender][collector][receiver];
        uint256 thawEnd = account.thawEndTimestamp;

        // No-op if not thawing or thaw period has not elapsed
        if (thawEnd == 0 || block.timestamp <= thawEnd) return 0;

        tokens = account.tokensThawing;
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
        uint256 dataServiceCut,
        address receiverDestination
    ) external override notPaused {
        // Check if there are enough funds in the escrow account
        EscrowAccount storage account = _escrowAccounts[payer][msg.sender][receiver];
        require(account.balance >= tokens, PaymentsEscrowInsufficientBalance(account.balance, tokens));

        // Reduce amount from account balance
        account.balance -= tokens;

        // Cap tokensThawing so the invariant tokensThawing <= balance is preserved
        if (account.balance < account.tokensThawing) {
            account.tokensThawing = account.balance;
            if (account.tokensThawing == 0) account.thawEndTimestamp = 0;
        }

        uint256 escrowBalanceBefore = _graphToken().balanceOf(address(this));

        _graphToken().approve(address(_graphPayments()), tokens);
        _graphPayments().collect(paymentType, receiver, tokens, dataService, dataServiceCut, receiverDestination);

        // Verify that the escrow balance is consistent with the collected tokens
        uint256 escrowBalanceAfter = _graphToken().balanceOf(address(this));
        require(
            escrowBalanceBefore == tokens + escrowBalanceAfter,
            PaymentsEscrowInconsistentCollection(escrowBalanceBefore, escrowBalanceAfter, tokens)
        );

        emit EscrowCollected(paymentType, payer, msg.sender, receiver, tokens, receiverDestination);
    }

    /// @inheritdoc IPaymentsEscrow
    function getEscrowAccount(
        address payer,
        address collector,
        address receiver
    ) external view override returns (EscrowAccount memory) {
        return _escrowAccounts[payer][collector][receiver];
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
        _escrowAccounts[_payer][_collector][_receiver].balance += _tokens;
        _graphToken().pullTokens(msg.sender, _tokens);
        emit Deposit(_payer, _collector, _receiver, _tokens);
    }

    /**
     * @notice Shared implementation for thaw and cancelThaw.
     * Sets tokensThawing to `min(tokensToThaw, balance)`. Resets the timer when the
     * thaw amount increases. When `evenIfTimerReset` is false and the operation would
     * increase the thaw amount (resetting the timer), the call is a no-op.
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokensToThaw The desired amount of tokens to thaw
     * @param evenIfTimerReset If true, always proceed. If false, skip increases that would reset the timer.
     * @return tokensThawing The resulting amount of tokens thawing
     */
    function _thaw(
        address collector,
        address receiver,
        uint256 tokensToThaw,
        bool evenIfTimerReset
    ) private returns (uint256 tokensThawing) {
        EscrowAccount storage account = _escrowAccounts[msg.sender][collector][receiver];
        uint256 currentThawing = account.tokensThawing;

        tokensThawing = tokensToThaw < account.balance ? tokensToThaw : account.balance;

        if (tokensThawing == currentThawing) return tokensThawing;

        uint256 thawEndTimestamp;
        if (tokensThawing < currentThawing) {
            // Decreasing (or canceling): preserve timer, clear if fully canceled
            account.tokensThawing = tokensThawing;
            if (tokensThawing == 0) account.thawEndTimestamp = 0;
            else thawEndTimestamp = account.thawEndTimestamp;
        } else {
            thawEndTimestamp = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
            uint256 currentThawEnd = account.thawEndTimestamp;
            // Increasing: reset timer (skip if evenIfTimerReset=false and timer would change)
            if (!evenIfTimerReset && currentThawEnd != 0 && currentThawEnd != thawEndTimestamp) return currentThawing;
            account.tokensThawing = tokensThawing;
            account.thawEndTimestamp = thawEndTimestamp;
        }

        emit Thawing(msg.sender, collector, receiver, tokensThawing, thawEndTimestamp);
    }
}
