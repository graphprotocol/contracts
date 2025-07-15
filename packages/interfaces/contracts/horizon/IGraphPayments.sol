// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title Interface for the {GraphPayments} contract
 * @notice This contract is part of the Graph Horizon payments protocol. It's designed
 * to pull funds (GRT) from the {PaymentsEscrow} and distribute them according to a
 * set of pre established rules.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
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
     * @param paymentType The type of payment as defined in {IGraphPayments}
     * @param payer The address of the payer
     * @param receiver The address of the receiver
     * @param dataService The address of the data service
     * @param tokens The total amount of tokens being collected
     * @param tokensProtocol Amount of tokens charged as protocol tax
     * @param tokensDataService Amount of tokens for the data service
     * @param tokensDelegationPool Amount of tokens for delegators
     * @param tokensReceiver Amount of tokens for the receiver
     * @param receiverDestination The address where the receiver's payment cut is sent.
     */
    event GraphPaymentCollected(
        PaymentTypes indexed paymentType,
        address indexed payer,
        address receiver,
        address indexed dataService,
        uint256 tokens,
        uint256 tokensProtocol,
        uint256 tokensDataService,
        uint256 tokensDelegationPool,
        uint256 tokensReceiver,
        address receiverDestination
    );

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
     * @notice Returns the protocol payment cut
     * @return The protocol payment cut in PPM
     */
    function PROTOCOL_PAYMENT_CUT() external view returns (uint256);

    /**
     * @notice Initialize the contract
     */
    function initialize() external;

    /**
     * @notice Collects funds from a payer.
     * It will pay cuts to all relevant parties and forward the rest to the receiver destination address. If the
     * destination address is zero the funds are automatically staked to the receiver. Note that the receiver
     * destination address can be set to the receiver address to collect funds on the receiver without re-staking.
     *
     * Note that the collected amount can be zero.
     *
     * @param paymentType The type of payment as defined in {IGraphPayments}
     * @param receiver The address of the receiver
     * @param tokens The amount of tokens being collected.
     * @param dataService The address of the data service
     * @param dataServiceCut The data service cut in PPM
     * @param receiverDestination The address where the receiver's payment cut is sent.
     */
    function collect(
        PaymentTypes paymentType,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination
    ) external;
}
