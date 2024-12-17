// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

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
     * @param tokens The total amount of tokens being collected
     * @param tokensProtocol Amount of tokens charged as protocol tax
     * @param tokensDataService Amount of tokens for the data service
     * @param tokensDelegationPool Amount of tokens for delegators
     * @param tokensReceiver Amount of tokens for the receiver
     */
    event GraphPaymentCollected(
        address indexed payer,
        address indexed receiver,
        address indexed dataService,
        uint256 tokens,
        uint256 tokensProtocol,
        uint256 tokensDataService,
        uint256 tokensDelegationPool,
        uint256 tokensReceiver
    );

    /**
     * @notice Thrown when the calculated amount of tokens to be paid out to all parties is
     * not the same as the amount of tokens being collected
     * @param tokens The amount of tokens being collected
     * @param tokensCalculated The sum of all the tokens to be paid out
     */
    error GraphPaymentsBadAccounting(uint256 tokens, uint256 tokensCalculated);

    /**
     * @notice Thrown when the protocol payment cut is invalid
     * @param protocolPaymentCut The protocol payment cut
     */
    error GraphPaymentsInvalidProtocolPaymentCut(uint256 protocolPaymentCut);

    /**
     * @notice Thrown when trying to use a cut that is not expressed in PPM
     * @param cut The cut
     */
    error GraphPaymentsInvalidCut(uint256 cut);

    /**
     * @notice Collects funds from a payer.
     * It will pay cuts to all relevant parties and forward the rest to the receiver.
     * @param paymentType The type of payment as defined in {IGraphPayments}
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens being collected
     * @param dataService The address of the data service
     * @param dataServiceCut The data service cut in PPM
     */
    function collect(
        PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut
    ) external;
}
