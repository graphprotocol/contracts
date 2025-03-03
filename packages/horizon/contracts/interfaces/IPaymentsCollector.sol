// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphPayments } from "./IGraphPayments.sol";

/**
 * @title Interface for a payments collector contract as defined by Graph Horizon payments protocol
 * @notice Contracts implementing this interface can be used with the payments protocol. First, a payer must
 * approve the collector to collect payments on their behalf. Only then can payment collection be initiated
 * using the collector contract.
 *
 * @dev It's important to note that it's the collector contract's responsibility to validate the payment
 * request is legitimate.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IPaymentsCollector {
    /**
     * @notice Emitted when a payment is collected
     * @param paymentType The payment type collected as defined by {IGraphPayments}
     * @param collectionId The id for the collection. Can be used at the discretion of the collector to group multiple payments.
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param dataService The address of the data service
     * @param tokens The amount of tokens being collected
     */
    event PaymentCollected(
        IGraphPayments.PaymentTypes paymentType,
        bytes32 indexed collectionId,
        address indexed payer,
        address receiver,
        address indexed dataService,
        uint256 tokens
    );

    /**
     * @notice Initiate a payment collection through the payments protocol
     * @dev This function should require the caller to present some form of evidence of the payer's debt to
     * the receiver. The collector should validate this evidence and, if valid, collect the payment.
     *
     * Emits a {PaymentCollected} event
     *
     * @param paymentType The payment type to collect, as defined by {IGraphPayments}
     * @param data Additional data required for the payment collection. Will vary depending on the collector
     * implementation.
     * @return The amount of tokens collected
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes memory data) external returns (uint256);
}
