// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

/**
 * @title Interface for the {GraphPayments} contract
 * @notice This contract is part of the Graph Horizon payments protocol. It's designed
 * to pull funds (GRT) from the {PaymentsEscrow} and distribute them according to a
 * set of pre established rules.
 */
interface IGraphPayments {
    /**
     * @notice Types of payments that are supported by the payments protocol
     * @dev
     */
    enum PaymentTypes {
        QueryFee,
        IndexingFee,
        IndexingRewards
    }

    /**
     * @notice Emitted when a payment is collected
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param dataService The address of the data service
     * @param tokensReceiver Amount of tokens for the receiver
     * @param tokensDelegationPool Amount of tokens for delegators
     * @param tokensDataService Amount of tokens for the data service
     * @param tokensProtocol Amount of tokens charged as protocol tax
     */
    event PaymentCollected(
        address indexed payer,
        address indexed receiver,
        address indexed dataService,
        uint256 tokensReceiver,
        uint256 tokensDelegationPool,
        uint256 tokensDataService,
        uint256 tokensProtocol
    );

    /**
     * @notice Thrown when there are insufficient tokens to pay the required amount
     * @param tokens The amount of tokens available
     * @param minTokens The amount of tokens being collected
     */
    error GraphPaymentsInsufficientTokens(uint256 tokens, uint256 minTokens);

    /**
     * @notice Thrown when the protocol payment cut is invalid
     * @param protocolPaymentCut The protocol payment cut
     */
    error GraphPaymentsInvalidProtocolPaymentCut(uint256 protocolPaymentCut);

    /**
     * @notice Collects funds from a payer.
     * It will pay cuts to all relevant parties and forward the rest to the receiver.
     * @param paymentType The type of payment as defined in {IGraphPayments}
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens being collected
     * @param dataService The address of the data service
     * @param tokensDataService The amount of tokens that should be sent to the data service
     */
    function collect(
        PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 tokensDataService
    ) external;
}
