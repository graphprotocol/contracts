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
    /// @notice The state of an agreement
    enum AgreementState {
        NotAccepted,
        Accepted,
        CanceledByServiceProvider,
        CanceledByPayer
    }

    /// @notice The party that can cancel an agreement
    enum CancelAgreementBy {
        ServiceProvider,
        Payer,
        ThirdParty
    }

    /// @notice Reasons why an agreement is not collectable
    enum AgreementNotCollectableReason {
        None,
        InvalidAgreementState,
        ZeroCollectionSeconds,
        InvalidTemporalWindow
    }

    /**
     * @notice A representation of a signed Recurring Collection Agreement (RCA)
     * @param rca The Recurring Collection Agreement to be signed
     * @param signature The signature of the RCA - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
     */
    struct SignedRCA {
        RecurringCollectionAgreement rca;
        bytes signature;
    }

    /**
     * @notice The Recurring Collection Agreement (RCA)
     * @param deadline The deadline for accepting the RCA
     * @param endsAt The timestamp when the agreement ends
     * @param payer The address of the payer the RCA was issued by
     * @param dataService The address of the data service the RCA was issued to
     * @param serviceProvider The address of the service provider the RCA was issued to
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * on top of the amount allowed for subsequent collections
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * except for the first collection
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum amount of seconds that can pass between collections
     * @param nonce A unique nonce for preventing collisions (user-chosen)
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     *
     */
    struct RecurringCollectionAgreement {
        uint64 deadline;
        uint64 endsAt;
        address payer;
        address dataService;
        address serviceProvider;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        uint256 nonce;
        bytes metadata;
    }

    /**
     * @notice A representation of a signed Recurring Collection Agreement Update (RCAU)
     * @param rcau The Recurring Collection Agreement Update to be signed
     * @param signature The signature of the RCAU - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
     */
    struct SignedRCAU {
        RecurringCollectionAgreementUpdate rcau;
        bytes signature;
    }

    /**
     * @notice The Recurring Collection Agreement Update (RCAU)
     * @param agreementId The agreement ID of the RCAU
     * @param deadline The deadline for upgrading the RCA
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * on top of the amount allowed for subsequent collections
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * except for the first collection
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum amount of seconds that can pass between collections
     * @param nonce The nonce for preventing replay attacks (must be current nonce + 1)
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     */
    struct RecurringCollectionAgreementUpdate {
        bytes16 agreementId;
        uint64 deadline;
        uint64 endsAt;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        uint32 nonce;
        bytes metadata;
    }

    /**
     * @notice The data for an agreement
     * @dev This struct is used to store the data of an agreement in the contract
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     * @param acceptedAt The timestamp when the agreement was accepted
     * @param lastCollectionAt The timestamp when the agreement was last collected at
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * on top of the amount allowed for subsequent collections
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * except for the first collection
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum amount of seconds that can pass between collections
     * @param updateNonce The current nonce for updates (prevents replay attacks)
     * @param canceledAt The timestamp when the agreement was canceled
     * @param state The state of the agreement
     */
    struct AgreementData {
        address dataService;
        address payer;
        address serviceProvider;
        uint64 acceptedAt;
        uint64 lastCollectionAt;
        uint64 endsAt;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        uint32 updateNonce;
        uint64 canceledAt;
        AgreementState state;
    }

    /**
     * @notice The params for collecting an agreement
     * @param agreementId The agreement ID of the RCA
     * @param collectionId The collection ID of the RCA
     * @param tokens The amount of tokens to collect
     * @param dataServiceCut The data service cut in parts per million
     * @param receiverDestination The address where the collected fees should be sent
     * @param maxSlippage Max acceptable tokens to lose due to rate limiting, or type(uint256).max to ignore
     */
    struct CollectParams {
        bytes16 agreementId;
        bytes32 collectionId;
        uint256 tokens;
        uint256 dataServiceCut;
        address receiverDestination;
        uint256 maxSlippage;
    }

    /**
     * @notice Emitted when an agreement is accepted
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     * @param agreementId The agreement ID
     * @param acceptedAt The timestamp when the agreement was accepted
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum amount of seconds that can pass between collections
     */
    event AgreementAccepted(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint64 acceptedAt,
        uint64 endsAt,
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
     * @param agreementId The agreement ID
     * @param canceledAt The timestamp when the agreement was canceled
     * @param canceledBy The party that canceled the agreement
     */
    event AgreementCanceled(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint64 canceledAt,
        CancelAgreementBy canceledBy
    );

    /**
     * @notice Emitted when an agreement is updated
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     * @param agreementId The agreement ID
     * @param updatedAt The timestamp when the agreement was updated
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum amount of seconds that can pass between collections
     */
    event AgreementUpdated(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        uint64 updatedAt,
        uint64 endsAt,
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
     * @param agreementId The agreement ID
     * @param collectionId The collection ID
     * @param tokens The amount of tokens collected
     * @param dataServiceCut The tokens cut for the data service
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
     * @notice Thrown when accepting an agreement with a zero ID
     */
    error RecurringCollectorAgreementIdZero();

    /**
     * @notice Thrown when interacting with an agreement not owned by the message sender
     * @param agreementId The agreement ID
     * @param unauthorizedDataService The address of the unauthorized data service
     */
    error RecurringCollectorDataServiceNotAuthorized(bytes16 agreementId, address unauthorizedDataService);

    /**
     * @notice Thrown when the data service is not authorized for the service provider
     * @param dataService The address of the unauthorized data service
     */
    error RecurringCollectorUnauthorizedDataService(address dataService);

    /**
     * @notice Thrown when interacting with an agreement with an elapsed deadline
     * @param currentTimestamp The current timestamp
     * @param deadline The elapsed deadline timestamp
     */
    error RecurringCollectorAgreementDeadlineElapsed(uint256 currentTimestamp, uint64 deadline);

    /**
     * @notice Thrown when the signer is invalid
     */
    error RecurringCollectorInvalidSigner();

    /**
     * @notice Thrown when the payment type is not IndexingFee
     * @param invalidPaymentType The invalid payment type
     */
    error RecurringCollectorInvalidPaymentType(IGraphPayments.PaymentTypes invalidPaymentType);

    /**
     * @notice Thrown when the caller is not the data service the RCA was issued to
     * @param unauthorizedCaller The address of the caller
     * @param dataService The address of the data service
     */
    error RecurringCollectorUnauthorizedCaller(address unauthorizedCaller, address dataService);

    /**
     * @notice Thrown when calling collect() with invalid data
     * @param invalidData The invalid data
     */
    error RecurringCollectorInvalidCollectData(bytes invalidData);

    /**
     * @notice Thrown when interacting with an agreement that has an incorrect state
     * @param agreementId The agreement ID
     * @param incorrectState The incorrect state
     */
    error RecurringCollectorAgreementIncorrectState(bytes16 agreementId, AgreementState incorrectState);

    /**
     * @notice Thrown when an agreement is not collectable
     * @param agreementId The agreement ID
     * @param reason The reason why the agreement is not collectable
     */
    error RecurringCollectorAgreementNotCollectable(bytes16 agreementId, AgreementNotCollectableReason reason);

    /**
     * @notice Thrown when accepting an agreement with an address that is not set
     */
    error RecurringCollectorAgreementAddressNotSet();

    /**
     * @notice Thrown when accepting or upgrading an agreement with an elapsed endsAt
     * @param currentTimestamp The current timestamp
     * @param endsAt The agreement end timestamp
     */
    error RecurringCollectorAgreementElapsedEndsAt(uint256 currentTimestamp, uint64 endsAt);

    /**
     * @notice Thrown when accepting or upgrading an agreement with an invalid collection window
     * @param allowedMinCollectionWindow The allowed minimum collection window
     * @param minSecondsPerCollection The minimum seconds per collection
     * @param maxSecondsPerCollection The maximum seconds per collection
     */
    error RecurringCollectorAgreementInvalidCollectionWindow(
        uint32 allowedMinCollectionWindow,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection
    );

    /**
     * @notice Thrown when accepting or upgrading an agreement with an invalid duration
     * @param requiredMinDuration The required minimum duration
     * @param invalidDuration The invalid duration
     */
    error RecurringCollectorAgreementInvalidDuration(uint32 requiredMinDuration, uint256 invalidDuration);

    /**
     * @notice Thrown when calling collect() with zero collection seconds
     * @param agreementId The agreement ID
     * @param currentTimestamp The current timestamp
     * @param lastCollectionAt The timestamp when the last collection was done
     *
     */
    error RecurringCollectorZeroCollectionSeconds(
        bytes16 agreementId,
        uint256 currentTimestamp,
        uint64 lastCollectionAt
    );

    /**
     * @notice Thrown when calling collect() too soon
     * @param agreementId The agreement ID
     * @param secondsSinceLast Seconds since last collection
     * @param minSeconds Minimum seconds between collections
     */
    error RecurringCollectorCollectionTooSoon(bytes16 agreementId, uint32 secondsSinceLast, uint32 minSeconds);

    /**
     * @notice Thrown when calling collect() too late
     * @param agreementId The agreement ID
     * @param secondsSinceLast Seconds since last collection
     * @param maxSeconds Maximum seconds between collections
     */
    error RecurringCollectorCollectionTooLate(bytes16 agreementId, uint64 secondsSinceLast, uint32 maxSeconds);

    /**
     * @notice Thrown when calling update() with an invalid nonce
     * @param agreementId The agreement ID
     * @param expected The expected nonce
     * @param provided The provided nonce
     */
    error RecurringCollectorInvalidUpdateNonce(bytes16 agreementId, uint32 expected, uint32 provided);

    /**
     * @notice Thrown when collected tokens are less than requested beyond the allowed slippage
     * @param requested The amount of tokens requested to collect
     * @param actual The actual amount that would be collected
     * @param maxSlippage The maximum allowed slippage
     */
    error RecurringCollectorExcessiveSlippage(uint256 requested, uint256 actual, uint256 maxSlippage);

    /**
     * @dev Accept an indexing agreement.
     * @param signedRCA The signed Recurring Collection Agreement which is to be accepted.
     * @return agreementId The deterministically generated agreement ID
     */
    function accept(SignedRCA calldata signedRCA) external returns (bytes16 agreementId);

    /**
     * @dev Cancel an indexing agreement.
     * @param agreementId The agreement's ID.
     * @param by The party that is canceling the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external;

    /**
     * @dev Update an indexing agreement.
     * @param signedRCAU The signed Recurring Collection Agreement Update which is to be applied.
     */
    function update(SignedRCAU calldata signedRCAU) external;

    /**
     * @dev Computes the hash of a RecurringCollectionAgreement (RCA).
     * @param rca The RCA for which to compute the hash.
     * @return The hash of the RCA.
     */
    function hashRCA(RecurringCollectionAgreement calldata rca) external view returns (bytes32);

    /**
     * @dev Computes the hash of a RecurringCollectionAgreementUpdate (RCAU).
     * @param rcau The RCAU for which to compute the hash.
     * @return The hash of the RCAU.
     */
    function hashRCAU(RecurringCollectionAgreementUpdate calldata rcau) external view returns (bytes32);

    /**
     * @dev Recovers the signer address of a signed RecurringCollectionAgreement (RCA).
     * @param signedRCA The SignedRCA containing the RCA and its signature.
     * @return The address of the signer.
     */
    function recoverRCASigner(SignedRCA calldata signedRCA) external view returns (address);

    /**
     * @dev Recovers the signer address of a signed RecurringCollectionAgreementUpdate (RCAU).
     * @param signedRCAU The SignedRCAU containing the RCAU and its signature.
     * @return The address of the signer.
     */
    function recoverRCAUSigner(SignedRCAU calldata signedRCAU) external view returns (address);

    /**
     * @notice Gets an agreement.
     * @param agreementId The ID of the agreement to retrieve.
     * @return The AgreementData struct containing the agreement's data.
     */
    function getAgreement(bytes16 agreementId) external view returns (AgreementData memory);

    /**
     * @notice Get collection info for an agreement
     * @param agreement The agreement data
     * @return isCollectable Whether the agreement is in a valid state that allows collection attempts,
     * not that there are necessarily funds available to collect.
     * @return collectionSeconds The valid collection duration in seconds (0 if not collectable)
     * @return reason The reason why the agreement is not collectable (None if collectable)
     */
    function getCollectionInfo(
        AgreementData memory agreement
    ) external view returns (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason);

    /**
     * @notice Generate a deterministic agreement ID from agreement parameters
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param deadline The deadline for accepting the agreement
     * @param nonce A unique nonce for preventing collisions
     * @return agreementId The deterministically generated agreement ID
     */
    function generateAgreementId(
        address payer,
        address dataService,
        address serviceProvider,
        uint64 deadline,
        uint256 nonce
    ) external pure returns (bytes16 agreementId);
}
