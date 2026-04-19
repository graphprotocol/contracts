// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IAgreementCollector } from "./IAgreementCollector.sol";
import { IGraphPayments } from "./IGraphPayments.sol";
import { IAuthorizable } from "./IAuthorizable.sol";

/**
 * @title Interface for the {RecurringCollector} contract
 * @author Edge & Node
 * @dev Extends {IAgreementCollector} with Recurring Collection Agreement (RCA) specific
 * structures, methods, and validation rules.
 * @notice Implements a payments collector contract that can be used to collect
 * recurrent payments.
 */
interface IRecurringCollector is IAuthorizable, IAgreementCollector {
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
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     * @param conditions Bitmask of payer-declared conditions (e.g. CONDITION_ELIGIBILITY_CHECK)
     * @param nonce A unique nonce for preventing collisions (user-chosen)
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     *
     */
    // solhint-disable-next-line gas-struct-packing
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
        uint16 conditions;
        uint256 nonce;
        bytes metadata;
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
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     * @param conditions Bitmask of payer-declared conditions (e.g. CONDITION_ELIGIBILITY_CHECK)
     * @param nonce The nonce for preventing replay attacks (must be current nonce + 1)
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     */
    // solhint-disable-next-line gas-struct-packing
    struct RecurringCollectionAgreementUpdate {
        bytes16 agreementId;
        uint64 deadline;
        uint64 endsAt;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        uint16 conditions;
        uint32 nonce;
        bytes metadata;
    }

    /**
     * @notice The data for an agreement
     * @dev This struct is used to store the data of an agreement in the contract.
     * Fields are ordered for optimal storage packing (7 slots).
     * @param dataService The address of the data service
     * @param acceptedAt The timestamp when the agreement was accepted
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param payer The address of the payer
     * @param lastCollectionAt The timestamp when the agreement was last collected at
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     * @param serviceProvider The address of the service provider
     * @param endsAt The timestamp when the agreement ends
     * @param updateNonce The current nonce for updates (prevents replay attacks)
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * on top of the amount allowed for subsequent collections
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * except for the first collection
     * @param activeTermsHash EIP-712 hash of the currently active terms (RCA or RCAU)
     * @param canceledAt The timestamp when the agreement was canceled
     * @param conditions Bitmask of payer-declared conditions
     * @param state The state of the agreement
     */
    struct AgreementData {
        address dataService; //        20 bytes ─┐ slot 0 (32/32)
        uint64 acceptedAt; //           8 bytes ─┤
        uint32 minSecondsPerCollection; // 4 bytes ─┘
        address payer; //              20 bytes ─┐ slot 1 (32/32)
        uint64 lastCollectionAt; //     8 bytes ─┤
        uint32 maxSecondsPerCollection; // 4 bytes ─┘
        address serviceProvider; //    20 bytes ─┐ slot 2 (32/32)
        uint64 endsAt; //              8 bytes ─┤
        uint32 updateNonce; //          4 bytes ─┘
        uint256 maxInitialTokens; //   32 bytes ─── slot 3
        uint256 maxOngoingTokensPerSecond; // 32 bytes ─── slot 4
        bytes32 activeTermsHash; //    32 bytes ─── slot 5
        uint64 canceledAt; //           8 bytes ─┐ slot 6 (11/32)
        uint16 conditions; //           2 bytes ─┤
        AgreementState state; //        1 byte  ─┘
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
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     */
    event AgreementAccepted(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
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
     * @param canceledBy The party that canceled the agreement
     */
    event AgreementCanceled(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
        CancelAgreementBy canceledBy
    );

    /**
     * @notice Emitted when an agreement is updated
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     * @param agreementId The agreement ID
     * @param endsAt The timestamp when the agreement ends
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     */
    event AgreementUpdated(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes16 agreementId,
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
     * @notice Thrown when an agreement does not exist (no accepted state and no stored offer)
     * @param agreementId The agreement ID that was not found
     */
    error RecurringCollectorAgreementNotFound(bytes16 agreementId);

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
     * @notice Thrown when an agreement's endsAt is not strictly after its acceptance deadline.
     * @param deadline The offer acceptance deadline
     * @param endsAt The agreement end timestamp
     */
    error RecurringCollectorAgreementEndsBeforeDeadline(uint64 deadline, uint64 endsAt);

    /**
     * @notice Thrown when accepting or upgrading an agreement with an elapsed endsAt
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
     * @notice Thrown when calling collect() with a zero collection seconds
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
     * @notice Thrown when a contract payer's eligibility oracle denies the service provider
     * @param agreementId The agreement ID
     * @param serviceProvider The service provider that is not eligible
     */
    error RecurringCollectorCollectionNotEligible(bytes16 agreementId, address serviceProvider);

    /**
     * @notice Thrown when an offer sets CONDITION_ELIGIBILITY_CHECK but the payer
     * does not support IProviderEligibility (via ERC-165)
     * @param payer The payer address
     */
    error RecurringCollectorPayerDoesNotSupportEligibilityInterface(address payer);

    /**
     * @notice Thrown when the caller does not provide enough gas for the payer callback
     * after collection
     */
    error RecurringCollectorInsufficientCallbackGas();

    /**
     * @notice Thrown when the caller is not the governor
     * @param account The address of the caller
     */
    error RecurringCollectorNotGovernor(address account);

    /**
     * @notice Thrown when the caller is not a pause guardian
     * @param account The address of the caller
     */
    error RecurringCollectorNotPauseGuardian(address account);

    /**
     * @notice Thrown when setting a pause guardian to the same status
     * @param account The address of the pause guardian
     * @param allowed The (unchanged) allowed status
     */
    error RecurringCollectorPauseGuardianNoChange(address account, bool allowed);

    /**
     * @notice Thrown when accepting or updating with a hash that the signer cancelled via SCOPE_SIGNED
     * @param signer The signer who cancelled the offer
     * @param hash The cancelled EIP-712 hash
     */
    error RecurringCollectorOfferCancelled(address signer, bytes32 hash);

    /**
     * @notice Emitted when a pause guardian is set
     * @param account The address of the pause guardian
     * @param allowed The allowed status
     */
    event PauseGuardianSet(address indexed account, bool allowed);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when a payer callback (beforeCollection / afterCollection) reverts.
     * @dev The try/catch ensures provider liveness but this event enables off-chain
     * monitoring to detect repeated failures and trigger reconciliation.
     * @param agreementId The agreement ID
     * @param payer The payer contract whose callback reverted
     * @param stage Whether the failure occurred before or after collection
     */
    event PayerCallbackFailed(bytes16 indexed agreementId, address indexed payer, PayerCallbackStage stage);

    /**
     * @notice Emitted when an offer (RCA or RCAU) is stored via {IAgreementCollector.offer}
     * @param agreementId The agreement ID
     * @param payer The payer that stored the offer
     * @param offerType OFFER_TYPE_NEW or OFFER_TYPE_UPDATE
     * @param offerHash The EIP-712 hash of the stored offer
     */
    event OfferStored(bytes16 indexed agreementId, address indexed payer, uint8 indexed offerType, bytes32 offerHash);

    /**
     * @notice Emitted when a stored offer is cancelled via {IAgreementCollector.cancel}.
     * @dev Fired for SCOPE_PENDING cancellations that delete a stored RCA or RCAU offer entry.
     * @param caller The msg.sender of the cancel call (the payer for SCOPE_PENDING)
     * @param agreementId The agreement ID
     * @param hash The EIP-712 hash of the cancelled offer
     */
    event OfferCancelled(address indexed caller, bytes16 indexed agreementId, bytes32 indexed hash);

    /**
     * @notice Pauses the collector, blocking accept, update, collect, and cancel.
     * @dev Only callable by a pause guardian. Uses OpenZeppelin Pausable.
     */
    function pause() external;

    /**
     * @notice Unpauses the collector.
     * @dev Only callable by a pause guardian.
     */
    function unpause() external;

    /**
     * @notice Returns the status of a pause guardian.
     * @param pauseGuardian The address to check
     * @return Whether the address is a pause guardian
     */
    function pauseGuardians(address pauseGuardian) external view returns (bool);

    /**
     * @notice Accept a Recurring Collection Agreement.
     * @dev Caller must be the data service the RCA was issued to.
     * If `signature` is non-empty: checks `rca.deadline >= block.timestamp` and verifies the ECDSA signature.
     * If `signature` is empty: the payer must be a contract implementing {IAgreementOwner.approveAgreement}
     * and must return the magic value for the RCA's EIP712 hash.
     * @param rca The Recurring Collection Agreement to accept
     * @param signature ECDSA signature bytes, or empty for contract-approved agreements
     * @return agreementId The deterministically generated agreement ID
     */
    function accept(
        RecurringCollectionAgreement calldata rca,
        bytes calldata signature
    ) external returns (bytes16 agreementId);

    /**
     * @notice Cancel an indexing agreement.
     * @param agreementId The agreement's ID.
     * @param by The party that is canceling the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external;

    /**
     * @notice Update a Recurring Collection Agreement.
     * @dev Caller must be the data service for the agreement.
     * If `signature` is non-empty: checks `rcau.deadline >= block.timestamp` and verifies the ECDSA signature.
     * If `signature` is empty: the payer (stored in the agreement) must be a contract implementing
     * {IAgreementOwner.approveAgreement} and must return the magic value for the RCAU's EIP712 hash.
     * @param rcau The Recurring Collection Agreement Update to apply
     * @param signature ECDSA signature bytes, or empty for contract-approved updates
     */
    function update(RecurringCollectionAgreementUpdate calldata rcau, bytes calldata signature) external;

    /**
     * @notice Computes the hash of a RecurringCollectionAgreement (RCA).
     * @param rca The RCA for which to compute the hash.
     * @return The hash of the RCA.
     */
    function hashRCA(RecurringCollectionAgreement calldata rca) external view returns (bytes32);

    /**
     * @notice Computes the hash of a RecurringCollectionAgreementUpdate (RCAU).
     * @param rcau The RCAU for which to compute the hash.
     * @return The hash of the RCAU.
     */
    function hashRCAU(RecurringCollectionAgreementUpdate calldata rcau) external view returns (bytes32);

    /**
     * @notice Recovers the signer address of a signed RecurringCollectionAgreement (RCA).
     * @param rca The RCA whose hash was signed.
     * @param signature The ECDSA signature bytes.
     * @return The address of the signer.
     */
    function recoverRCASigner(
        RecurringCollectionAgreement calldata rca,
        bytes calldata signature
    ) external view returns (address);

    /**
     * @notice Recovers the signer address of a signed RecurringCollectionAgreementUpdate (RCAU).
     * @param rcau The RCAU whose hash was signed.
     * @param signature The ECDSA signature bytes.
     * @return The address of the signer.
     */
    function recoverRCAUSigner(
        RecurringCollectionAgreementUpdate calldata rcau,
        bytes calldata signature
    ) external view returns (address);

    /**
     * @notice Gets an agreement.
     * @param agreementId The ID of the agreement to retrieve.
     * @return The AgreementData struct containing the agreement's data.
     */
    function getAgreement(bytes16 agreementId) external view returns (AgreementData memory);

    /**
     * @notice Get collection info for an agreement
     * @param agreementId The agreement id
     * @return isCollectable Whether the agreement is in a valid state that allows collection attempts,
     * not that there are necessarily funds available to collect.
     * @return collectionSeconds The valid collection duration in seconds (0 if not collectable)
     * @return reason The reason why the agreement is not collectable (None if collectable)
     */
    function getCollectionInfo(
        bytes16 agreementId
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
