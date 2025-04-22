// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";
import { IGraphPayments } from "./IGraphPayments.sol";
import { IAuthorizable } from "./IAuthorizable.sol";

/**
 * @title Interface for the {RecurringCollector} contract
 * @dev Implements the {IPaymentCollector} interface as defined by the Graph
 * Horizon payments protocol.
 * @notice Implements a payments collector contract that can be used to collect
 * recurrent payments.
 */
interface IRecurringCollector is IAuthorizable, IPaymentsCollector {
    /// @notice A representation of a signed Recurring Collection Agreement (RCA)
    struct SignedRCA {
        // The RCA
        RecurringCollectionAgreement rca;
        // Signature - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
        bytes signature;
    }

    /// @notice The Recurring Collection Agreement (RCA)
    struct RecurringCollectionAgreement {
        // The agreement ID of the RCA
        bytes16 agreementId;
        // The deadline for accepting the RCA
        uint256 deadline;
        // The duration of the RCA in seconds
        uint256 duration;
        // The address of the payer the RCA was issued by
        address payer;
        // The address of the data service the RCA was issued to
        address dataService;
        // The address of the service provider the RCA was issued to
        address serviceProvider;
        // The maximum amount of tokens that can be collected in the first collection
        // on top of the amount allowed for subsequent collections
        uint256 maxInitialTokens;
        // The maximum amount of tokens that can be collected per second
        // except for the first collection
        uint256 maxOngoingTokensPerSecond;
        // The minimum amount of seconds that must pass between collections
        uint32 minSecondsPerCollection;
        // The maximum amount of seconds that can pass between collections
        uint32 maxSecondsPerCollection;
        // Arbitrary metadata to extend functionality if a data service requires it
        bytes metadata;
    }

    /// @notice A representation of a signed Recurring Collection Agreement Upgrade (RCAU)
    struct SignedRCAU {
        // The RCAU
        RecurringCollectionAgreementUpgrade rcau;
        // Signature - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
        bytes signature;
    }

    struct RecurringCollectionAgreementUpgrade {
        // The agreement ID
        bytes16 agreementId;
        // The deadline for upgrading
        uint256 deadline;
        // The duration of the agreement in seconds
        uint256 duration;
        // The maximum amount of tokens that can be collected in the first collection
        // on top of the amount allowed for subsequent collections
        uint256 maxInitialTokens;
        // The maximum amount of tokens that can be collected per second
        // except for the first collection
        uint256 maxOngoingTokensPerSecond;
        // The minimum amount of seconds that must pass between collections
        uint32 minSecondsPerCollection;
        // The maximum amount of seconds that can pass between collections
        uint32 maxSecondsPerCollection;
        // Arbitrary metadata to extend functionality if a data service requires it
        bytes metadata;
    }

    /// @notice The data for an agreement
    struct AgreementData {
        // The address of the data service
        address dataService;
        // The address of the payer
        address payer;
        // The address of the service provider
        address serviceProvider;
        // The timestamp when the agreement was accepted
        uint256 acceptedAt;
        // The timestamp when the agreement was last collected at
        uint256 lastCollectionAt;
        // The duration of the agreement in seconds
        uint256 duration;
        // The maximum amount of tokens that can be collected in the first collection
        // on top of the amount allowed for subsequent collections
        uint256 maxInitialTokens;
        // The maximum amount of tokens that can be collected per second
        // except for the first collection
        uint256 maxOngoingTokensPerSecond;
        // The minimum amount of seconds that must pass between collections
        uint32 minSecondsPerCollection;
        // The maximum amount of seconds that can pass between collections
        uint32 maxSecondsPerCollection;
    }

    /// @notice The params for collecting an agreement
    struct CollectParams {
        bytes16 agreementId;
        // The collection ID
        bytes32 collectionId;
        // The amount of tokens to collect
        uint256 tokens;
        // The data service cut in PPM
        uint256 dataServiceCut;
    }

    /**
     * @notice Emitted when an agreement is accepted
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     */
    event AgreementAccepted(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint256 acceptedAt,
        uint256 duration,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection
    );

    /**
     * @notice Emitted when an agreement is canceled
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     */
    event AgreementCanceled(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint256 canceledAt
    );

    /**
     * @notice Emitted when an agreement is upgraded
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     */
    event AgreementUpgraded(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint256 upgradedAt,
        uint256 duration,
        uint256 maxInitialTokens,
        uint256 maxOngoingTokensPerSecond,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection
    );

    /**
     * @notice Emitted when an RCA is collected
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     */
    event RCACollected(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        bytes32 collectionId,
        uint256 tokens,
        uint256 dataServiceCut
    );

    /**
     * Thrown when interacting with an agreement not owned by the message sender
     * @param agreementId The agreement ID
     * @param unauthorizedDataService The address of the unauthorized data service
     */
    error RecurringCollectorDataServiceNotAuthorized(bytes16 agreementId, address unauthorizedDataService);

    /**
     * Thrown when interacting with an agreement with an elapsed deadline
     * @param elapsedAt The timestamp when the deadline elapsed
     */
    error RecurringCollectorAgreementDeadlineElapsed(uint256 elapsedAt);

    /**
     * Thrown when the signer is invalid
     */
    error RecurringCollectorInvalidSigner();

    /**
     * Thrown when the payment type is not IndexingFee
     * @param invalidPaymentType The invalid payment type
     */
    error RecurringCollectorInvalidPaymentType(IGraphPayments.PaymentTypes invalidPaymentType);

    /**
     * Thrown when the caller is not the data service the RCA was issued to
     * @param unauthorizedCaller The address of the caller
     * @param dataService The address of the data service
     */
    error RecurringCollectorUnauthorizedCaller(address unauthorizedCaller, address dataService);

    /**
     * Thrown when calling collect() with invalid data
     * @param invalidData The invalid data
     */
    error RecurringCollectorInvalidCollectData(bytes invalidData);

    /**
     * Thrown when calling accept() for an already accepted agreement
     * @param agreementId The agreement ID
     */
    error RecurringCollectorAgreementAlreadyAccepted(bytes16 agreementId);

    /**
     * Thrown when interacting with an agreement that was never accepted
     * @param agreementId The agreement ID
     */
    error RecurringCollectorAgreementNeverAccepted(bytes16 agreementId);

    /**
     * Thrown when interacting with an agreement that was canceled
     * @param agreementId The agreement ID
     */
    error RecurringCollectorAgreementCanceled(bytes16 agreementId);

    /**
     * Thrown when accepting or upgrading an agreement with invalid parameters
     */
    error RecurringCollectorAgreementInvalidParameters();

    /**
     * Thrown when calling collect() on an elapsed agreement
     * @param agreementId The agreement ID
     * @param agreementEnd The agreement end timestamp
     */
    error RecurringCollectorAgreementElapsed(bytes16 agreementId, uint256 agreementEnd);

    /**
     * Thrown when calling collect() too soon
     * @param agreementId The agreement ID
     * @param secondsSinceLast Seconds since last collection
     * @param minSeconds Minimum seconds between collections
     */
    error RecurringCollectorCollectionTooSoon(bytes16 agreementId, uint256 secondsSinceLast, uint256 minSeconds);

    /**
     * Thrown when calling collect() too late
     * @param agreementId The agreement ID
     * @param secondsSinceLast Seconds since last collection
     * @param maxSeconds Maximum seconds between collections
     */
    error RecurringCollectorCollectionTooLate(bytes16 agreementId, uint256 secondsSinceLast, uint256 maxSeconds);

    /**
     * Thrown when calling collect() too late
     * @param agreementId The agreement ID
     * @param tokens The amount of tokens to collect
     * @param maxTokens The maximum amount of tokens allowed to collect
     */
    error RecurringCollectorCollectAmountTooHigh(bytes16 agreementId, uint256 tokens, uint256 maxTokens);

    /**
     * @dev Accept an indexing agreement.
     * @param signedRCA The signed Recurring Collection Agreement which is to be accepted.
     */
    function accept(SignedRCA calldata signedRCA) external;

    /**
     * @dev Cancel an indexing agreement.
     * @param agreementId The agreement's ID.
     */
    function cancel(bytes16 agreementId) external;

    /**
     * @dev Upgrade an indexing agreement.
     */
    function upgrade(SignedRCAU calldata signedRCAU) external;

    /**
     * @dev Computes the hash of a RecurringCollectionAgreement (RCA).
     * @param rca The RCA for which to compute the hash.
     * @return The hash of the RCA.
     */
    function encodeRCA(RecurringCollectionAgreement calldata rca) external view returns (bytes32);

    /**
     * @dev Computes the hash of a RecurringCollectionAgreementUpgrade (RCAU).
     * @param rcau The RCAU for which to compute the hash.
     * @return The hash of the RCAU.
     */
    function encodeRCAU(RecurringCollectionAgreementUpgrade calldata rcau) external view returns (bytes32);

    /**
     * @dev Recovers the signer address of a signed RecurringCollectionAgreement (RCA).
     * @param signedRCA The SignedRCA containing the RCA and its signature.
     * @return The address of the signer.
     */
    function recoverRCASigner(SignedRCA calldata signedRCA) external view returns (address);

    /**
     * @dev Recovers the signer address of a signed RecurringCollectionAgreementUpgrade (RCAU).
     * @param signedRCAU The SignedRCAU containing the RCAU and its signature.
     * @return The address of the signer.
     */
    function recoverRCAUSigner(SignedRCAU calldata signedRCAU) external view returns (address);

    /**
     * @notice Gets an agreement.
     */
    function getAgreement(bytes16 agreementId) external view returns (AgreementData memory);
}
