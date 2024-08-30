// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IGraphPayments } from "./IGraphPayments.sol";

/**
 * @title Interface for the {PaymentsEscrow} contract
 * @notice This contract is part of the Graph Horizon payments protocol. It holds the funds (GRT)
 * for payments made through the payments protocol for services provided
 * via a Graph Horizon data service.
 *
 * Payers deposit funds on the escrow, signalling their ability to pay for a service, and only
 * being able to retrieve them after a thawing period. Receivers collect funds from the escrow,
 * provided the payer has authorized them. The payer authorization is delegated to a payment
 * collector contract which implements the {IPaymentsCollector} interface.
 */
interface IPaymentsEscrow {
    /// @notice Escrow account for a payer-receiver pair
    struct EscrowAccount {
        // Total token balance for the payer-receiver pair
        uint256 balance;
        // Amount of tokens currently being thawed
        uint256 tokensThawing;
        // Timestamp at which thawing period ends (zero if not thawing)
        uint256 thawEndTimestamp;
    }

    /// @notice Details for a payer-collector pair
    /// @dev Collectors can be removed only after a thawing period
    struct Collector {
        // Amount of tokens the collector is allowed to collect
        uint256 allowance;
        // Timestamp at which the collector thawing period ends (zero if not thawing)
        uint256 thawEndTimestamp;
    }

    /**
     * @notice Emitted when a payer authorizes a collector to collect funds
     * @param payer The address of the payer
     * @param collector The address of the collector
     */
    event AuthorizedCollector(address indexed payer, address indexed collector);

    /**
     * @notice Emitted when a payer thaws a collector
     * @param payer The address of the payer
     * @param collector The address of the collector
     */
    event ThawCollector(address indexed payer, address indexed collector);

    /**
     * @notice Emitted when a payer cancels the thawing of a collector
     * @param payer The address of the payer
     * @param collector The address of the collector
     */
    event CancelThawCollector(address indexed payer, address indexed collector);

    /**
     * @notice Emitted when a payer revokes a collector authorization.
     * @param payer The address of the payer
     * @param collector The address of the collector
     */
    event RevokeCollector(address indexed payer, address indexed collector);

    /**
     * @notice Emitted when a payer deposits funds into the escrow for a payer-receiver pair
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens deposited
     */
    event Deposit(address indexed payer, address indexed receiver, uint256 tokens);

    /**
     * @notice Emitted when a payer cancels an escrow thawing
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     */
    event CancelThaw(address indexed payer, address indexed receiver);

    /**
     * @notice Emitted when a payer thaws funds from the escrow for a payer-receiver pair
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens being thawed
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event Thaw(address indexed payer, address indexed receiver, uint256 tokens, uint256 thawEndTimestamp);

    /**
     * @notice Emitted when a payer withdraws funds from the escrow for a payer-receiver pair
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens withdrawn
     */
    event Withdraw(address indexed payer, address indexed receiver, uint256 tokens);

    /**
     * @notice Emitted when a collector collects funds from the escrow for a payer-receiver pair
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens collected
     */
    event EscrowCollected(address indexed payer, address indexed receiver, uint256 tokens);

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
     * @notice Thrown when setting the thawing period to a value greater than the maximum
     * @param thawingPeriod The thawing period
     * @param maxThawingPeriod The maximum thawing period
     */
    error PaymentsEscrowThawingPeriodTooLong(uint256 thawingPeriod, uint256 maxThawingPeriod);

    /**
     * @notice Thrown when a collector has insufficient allowance to collect funds
     * @param allowance The current allowance
     * @param minAllowance The minimum required allowance
     */
    error PaymentsEscrowInsufficientAllowance(uint256 allowance, uint256 minAllowance);

    /**
     * @notice Thrown when the contract balance is not consistent with the collection amount
     * @param balanceBefore The balance before the collection
     * @param balanceAfter The balance after the collection
     * @param tokens The amount of tokens collected
     */
    error PaymentsEscrowInconsistentCollection(uint256 balanceBefore, uint256 balanceAfter, uint256 tokens);

    /**
     * @notice Thrown when operating a zero token amount is not allowed.
     */
    error PaymentsEscrowInvalidZeroTokens();

    /**
     * @notice Authorize a collector to collect funds from the payer's escrow
     * @dev This function can only be used to increase the allowance of a collector.
     * To reduce it the authorization must be revoked and a new one must be created.
     *
     * Requirements:
     * - `allowance` must be greater than zero
     *
     * Emits an {AuthorizedCollector} event
     *
     * @param collector The address of the collector
     * @param allowance The amount of tokens to add to the collector's allowance
     */
    function approveCollector(address collector, uint256 allowance) external;

    /**
     * @notice Thaw a collector's collector authorization
     * @dev The thawing period is defined by the `REVOKE_COLLECTOR_THAWING_PERIOD` constant
     *
     * Emits a {ThawCollector} event
     *
     * @param collector The address of the collector
     */
    function thawCollector(address collector) external;

    /**
     * @notice Cancel a collector's authorization thawing
     * @dev Requirements:
     * - `collector` must be thawing
     *
     * Emits a {CancelThawCollector} event
     *
     * @param collector The address of the collector
     */
    function cancelThawCollector(address collector) external;

    /**
     * @notice Revoke a collector's authorization.
     * Removes the collector from the list of authorized collectors.
     * @dev Requirements:
     * - `collector` must have thawed
     *
     * Emits a {RevokeCollector} event
     *
     * @param collector The address of the collector
     */
    function revokeCollector(address collector) external;

    /**
     * @notice Deposits funds into the escrow for a payer-receiver pair, where
     * the payer is the transaction caller.
     * @dev Emits a {Deposit} event
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to deposit
     */
    function deposit(address receiver, uint256 tokens) external;

    /**
     * @notice Deposits funds into the escrow for a payer-receiver pair, where
     * the payer can be specified.
     * @dev Emits a {Deposit} event
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to deposit
     */
    function depositTo(address payer, address receiver, uint256 tokens) external;

    /**
     * @notice Thaw a specific amount of escrow from a payer-receiver's escrow account.
     * The payer is the transaction caller.
     * If `tokens` is zero and funds were already thawing it will cancel the thawing.
     * Note that repeated calls to this function will overwrite the previous thawing amount
     * and reset the thawing period.
     * @dev Requirements:
     * - `tokens` must be less than or equal to the available balance
     *
     * Emits a {Thaw} event. If `tokens` is zero it will emit a {CancelThaw} event.
     *
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to thaw
     */
    function thaw(address receiver, uint256 tokens) external;

    /**
     * @notice Withdraws all thawed escrow from a payer-receiver's escrow account.
     * The payer is the transaction caller.
     * Note that the withdrawn funds might be less than the thawed amount if there were
     * payment collections in the meantime.
     * @dev Requirements:
     * - Funds must be thawed
     *
     * Emits a {Withdraw} event
     *
     * @param receiver The address of the receiver
     */
    function withdraw(address receiver) external;

    /**
     * @notice Collects funds from the payer-receiver's escrow and sends them to {GraphPayments} for
     * distribution using the Graph Horizon Payments protocol.
     * The function will revert if there are not enough funds in the escrow.
     * @dev Requirements:
     * - `collector` needs to be authorized by the payer and have enough allowance
     *
     * Emits an {EscrowCollected} event
     *
     * @param paymentType The type of payment being collected as defined in the {IGraphPayments} interface
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens to collect
     * @param collector The address of the collector
     * @param tokensDataService The amount of tokens that {GraphPayments} should send to the data service
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address collector,
        uint256 tokensDataService
    ) external;

    /**
     * @notice Get the balance of a payer-receiver pair
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     */
    function getBalance(address payer, address receiver) external view returns (uint256);
}
