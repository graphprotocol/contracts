// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IGraphPayments } from "./IGraphPayments.sol";

/**
 * @title Interface for the {PaymentsEscrow} contract
 * @author Edge & Node
 * @notice This contract is part of the Graph Horizon payments protocol. It holds the funds (GRT)
 * for payments made through the payments protocol for services provided
 * via a Graph Horizon data service.
 *
 * Payers deposit funds on the escrow, signalling their ability to pay for a service, and only
 * being able to retrieve them after a thawing period. Receivers collect funds from the escrow,
 * provided the payer has authorized them. The payer authorization is delegated to a payment
 * collector contract which implements the {IPaymentsCollector} interface.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IPaymentsEscrow {
    /**
     * @notice Escrow account for a payer-collector-receiver tuple
     * @param balance The total token balance for the payer-collector-receiver tuple
     * @param tokensThawing The amount of tokens currently being thawed
     * @param thawEndTimestamp The timestamp at which thawing period ends (zero if not thawing)
     */
    struct EscrowAccount {
        uint256 balance;
        uint256 tokensThawing;
        uint256 thawEndTimestamp;
    }

    /**
     * @notice Emitted when a payer deposits funds into the escrow for a payer-collector-receiver tuple
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens deposited
     */
    event Deposit(address indexed payer, address indexed collector, address indexed receiver, uint256 tokens);

    /**
     * @notice Emitted when a payer cancels an escrow thawing
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokensThawing The amount of tokens that were being thawed
     * @param thawEndTimestamp The timestamp at which the thawing period was ending
     */
    event CancelThaw(
        address indexed payer,
        address indexed collector,
        address indexed receiver,
        uint256 tokensThawing,
        uint256 thawEndTimestamp
    );

    /**
     * @notice Emitted when a payer thaws funds from the escrow for a payer-collector-receiver tuple
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens being thawed
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event Thaw(
        address indexed payer,
        address indexed collector,
        address indexed receiver,
        uint256 tokens,
        uint256 thawEndTimestamp
    );

    /**
     * @notice Emitted when a payer withdraws funds from the escrow for a payer-collector-receiver tuple
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens withdrawn
     */
    event Withdraw(address indexed payer, address indexed collector, address indexed receiver, uint256 tokens);

    /**
     * @notice Emitted when a collector collects funds from the escrow for a payer-collector-receiver tuple
     * @param paymentType The type of payment being collected as defined in the {IGraphPayments} interface
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens collected
     * @param receiverDestination The address where the receiver's payment should be sent.
     */
    event EscrowCollected(
        IGraphPayments.PaymentTypes indexed paymentType,
        address indexed payer,
        address indexed collector,
        address receiver,
        uint256 tokens,
        address receiverDestination
    );

    // -- Errors --

    /**
     * @notice Thrown when a protected function is called and the contract is paused.
     */
    error PaymentsEscrowIsPaused();

    /**
     * @notice Thrown when the available balance is insufficient to perform an operation
     * @param balance The current balance
     * @param minBalance The minimum required balance
     */
    error PaymentsEscrowInsufficientBalance(uint256 balance, uint256 minBalance);

    /**
     * @notice Thrown when a thawing is expected to be in progress but it is not
     */
    error PaymentsEscrowNotThawing();

    /**
     * @notice Thrown when a thawing is still in progress
     * @param currentTimestamp The current timestamp
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    error PaymentsEscrowStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);

    /**
     * @notice Thrown when operating a zero token amount is not allowed.
     */
    error PaymentsEscrowInvalidZeroTokens();

    /**
     * @notice Thrown when setting the thawing period to a value greater than the maximum
     * @param thawingPeriod The thawing period
     * @param maxWaitPeriod The maximum wait period
     */
    error PaymentsEscrowThawingPeriodTooLong(uint256 thawingPeriod, uint256 maxWaitPeriod);

    /**
     * @notice Thrown when the contract balance is not consistent with the collection amount
     * @param balanceBefore The balance before the collection
     * @param balanceAfter The balance after the collection
     * @param tokens The amount of tokens collected
     */
    error PaymentsEscrowInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokens);

    /**
     * @notice The maximum thawing period for escrow funds withdrawal
     * @return The maximum thawing period in seconds
     */
    function MAX_WAIT_PERIOD() external view returns (uint256);

    /**
     * @notice The thawing period for escrow funds withdrawal
     * @return The thawing period in seconds
     */
    function WITHDRAW_ESCROW_THAWING_PERIOD() external view returns (uint256);

    /**
     * @notice Initialize the contract
     */
    function initialize() external;

    /**
     * @notice Deposits funds into the escrow for a payer-collector-receiver tuple, where
     * the payer is the transaction caller.
     * @dev Emits a {Deposit} event
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to deposit
     */
    function deposit(address collector, address receiver, uint256 tokens) external;

    /**
     * @notice Deposits funds into the escrow for a payer-collector-receiver tuple, where
     * the payer can be specified.
     * @dev Emits a {Deposit} event
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to deposit
     */
    function depositTo(address payer, address collector, address receiver, uint256 tokens) external;

    /**
     * @notice Sets the thawing amount for a payer-collector-receiver's escrow account.
     * The payer is the transaction caller.
     * Idempotent: if the target matches current thawing, this is a no-op.
     * Capped at balance: if `tokens` exceeds balance, thaws the entire balance.
     * Resets the thaw timer when the amount increases; preserves it when it decreases.
     * `thaw(collector, receiver, 0)` cancels all thawing.
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The desired amount of tokens to thaw
     * @return tokensThawing The resulting amount of tokens thawing after the operation
     * @dev Emits a {Thaw} event when the thaw amount increases.
     * Emits a {CancelThaw} event when thawing is fully canceled.
     */
    function thaw(address collector, address receiver, uint256 tokens) external returns (uint256 tokensThawing);

    /**
     * @notice Sets the thawing amount with a guard against timer reset.
     * When `evenIfTimerReset` is false and the operation would increase the thaw amount
     * (which resets the timer), the call is a no-op and returns the current tokensThawing.
     * Decreases and cancellations always proceed regardless of this flag.
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @param tokens The desired amount of tokens to thaw
     * @param evenIfTimerReset If true, always proceed. If false, skip increases that would reset the timer.
     * @return tokensThawing The resulting amount of tokens thawing after the operation
     */
    function thaw(
        address collector,
        address receiver,
        uint256 tokens,
        bool evenIfTimerReset
    ) external returns (uint256 tokensThawing);

    /**
     * @notice Cancels all thawing. Equivalent to `thaw(collector, receiver, 0)`.
     * Idempotent: if nothing is thawing, this is a no-op.
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @return tokensThawing The resulting amount of tokens thawing (always 0)
     * @dev Emits a {CancelThaw} event if any tokens were thawing.
     */
    function cancelThaw(address collector, address receiver) external returns (uint256 tokensThawing);

    /**
     * @notice Withdraws all thawed escrow from a payer-collector-receiver's escrow account.
     * The payer is the transaction caller.
     * Idempotent: returns 0 if nothing is thawing or thaw period has not elapsed.
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @return tokens The amount of tokens withdrawn
     * @dev Emits a {Withdraw} event if tokens were withdrawn.
     */
    function withdraw(address collector, address receiver) external returns (uint256 tokens);

    /**
     * @notice Collects funds from the payer-collector-receiver's escrow and sends them to {GraphPayments} for
     * distribution using the Graph Horizon Payments protocol.
     * The function will revert if there are not enough funds in the escrow.
     *
     * Emits an {EscrowCollected} event
     *
     * @param paymentType The type of payment being collected as defined in the {IGraphPayments} interface
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to collect
     * @param dataService The address of the data service
     * @param dataServiceCut The data service cut in PPM that {GraphPayments} should send
     * @param receiverDestination The address where the receiver's payment should be sent.
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination
    ) external;

    /**
     * @notice Get the balance of a payer-collector-receiver tuple
     * This function will return 0 if the current balance is less than the amount of funds being thawed.
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @return The balance of the payer-collector-receiver tuple
     */
    function getBalance(address payer, address collector, address receiver) external view returns (uint256);

    /**
     * @notice Escrow account details for a payer-collector-receiver tuple
     * @param payer The address of the payer
     * @param collector The address of the collector
     * @param receiver The address of the receiver
     * @return The escrow account details
     */
    function escrowAccounts(
        address payer,
        address collector,
        address receiver
    ) external view returns (EscrowAccount memory);
}
