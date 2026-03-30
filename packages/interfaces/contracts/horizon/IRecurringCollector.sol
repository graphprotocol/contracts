// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IAgreementCollector } from "./IAgreementCollector.sol";

/**
 * @title Interface for the {RecurringCollector} contract
 * @author Edge & Node
 * @dev Extends {IAgreementCollector} with Recurring Collection Agreement (RCA) specific
 * structures, methods, and validation rules.
 * @notice Implements a payments collector contract that can be used to collect
 * recurrent payments based on time-windowed pricing terms.
 */
interface IRecurringCollector is IAgreementCollector {
    // -- Structs --

    /**
     * @notice The params for collecting an agreement
     * @param agreementId The agreement ID
     * @param collectionId The collection ID
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

    // -- Enums --

    /// @dev Reasons why an agreement is not collectable
    enum AgreementNotCollectableReason {
        None,
        InvalidAgreementState,
        ZeroCollectionSeconds,
        InvalidTemporalWindow
    }

    /// @dev Reasons why a collection window is invalid
    enum InvalidCollectionWindowReason {
        None,
        ElapsedEndsAt,
        InvalidWindow,
        InsufficientDuration
    }

    // -- Events --

    /**
     * @notice Emitted on every agreement lifecycle change.
     * @param agreementId The agreement ID
     * @param versionHash The hash of the agreement terms version
     * @param state The agreement state flags after the change
     */
    event AgreementUpdated(bytes16 indexed agreementId, bytes32 versionHash, uint16 state);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when a payer callback reverts.
     * @param agreementId The agreement ID
     * @param payer The payer address
     * @param stage The callback stage at which the failure occurred
     */
    event PayerCallbackFailed(bytes16 indexed agreementId, address indexed payer, PayerCallbackStage stage);

    /**
     * @notice Emitted when an auto-update is attempted during the final collect.
     * @param agreementId The agreement ID
     * @param success Whether the auto-update succeeded
     */
    event AutoUpdateAttempted(bytes16 indexed agreementId, bool success);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when a pause guardian is set.
     * @param account The pause guardian address
     * @param allowed Whether the account is allowed as a pause guardian
     */
    event PauseGuardianSet(address indexed account, bool allowed);
    // solhint-disable-previous-line gas-indexed-events

    // -- Generic errors --

    error AgreementIdZero();
    error DataServiceNotAuthorized(bytes16 agreementId, address unauthorizedDataService);
    error UnauthorizedDataService(address dataService);
    error AgreementDeadlineElapsed(uint256 currentTimestamp, uint64 deadline);
    error UnauthorizedCaller(address unauthorizedCaller, address dataService);
    error InvalidCollectData(bytes invalidData);
    error AgreementIncorrectState(bytes16 agreementId, uint16 incorrectState);
    error AgreementNotCollectable(bytes16 agreementId, AgreementNotCollectableReason reason);
    error AgreementAddressNotSet();
    error AgreementInvalidCollectionWindow(
        InvalidCollectionWindowReason reason,
        uint32 minSecondsPerCollection,
        uint32 maxSecondsPerCollection
    );
    error AgreementHashMismatch(bytes16 agreementId, bytes32 expected, bytes32 provided);
    error AgreementTermsEmpty(bytes16 agreementId);
    error UnauthorizedPayer(address caller, address payer);
    error UnauthorizedServiceProvider(address caller, address serviceProvider);
    error InsufficientCallbackGas();
    error NotGovernor(address account);
    error NotPauseGuardian(address account);
    error InvalidOfferType(uint8 offerType);
    error ExcessiveSlippage(uint256 requested, uint256 actual, uint256 maxSlippage);

    // -- Pause guardian methods (pause/unpause/paused implemented via IPausableControl) --

    /**
     * @notice Check whether an account is a pause guardian.
     * @param pauseGuardian The address to check
     * @return Whether the account is a pause guardian
     */
    function isPauseGuardian(address pauseGuardian) external view returns (bool);

    // -- RCA-specific structures --

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
     * @param conditions Bitfield of agreement conditions (e.g. CONDITION_ELIGIBILITY_CHECK)
     * @param minSecondsPayerCancellationNotice Minimum seconds of notice the payer must give before
     * cancellation takes effect (enforced on cancel and OFFER_TYPE_UPDATE with WITH_NOTICE)
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
        uint32 minSecondsPayerCancellationNotice;
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
     * @param conditions Bitfield of agreement conditions (e.g. CONDITION_ELIGIBILITY_CHECK)
     * @param minSecondsPayerCancellationNotice Minimum seconds of notice the payer must give before
     * cancellation takes effect (enforced on cancel and OFFER_TYPE_UPDATE with WITH_NOTICE)
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
        uint32 minSecondsPayerCancellationNotice;
        uint32 nonce;
        bytes metadata;
    }

    /**
     * @notice The pricing and window terms for an agreement
     * @dev Shared between active and pending update terms in AgreementStorage.
     * Packed layout (4 fixed slots + dynamic):
     *   slot 0: deadline(8) + endsAt(8) + minSecondsPerCollection(4) + maxSecondsPerCollection(4) + conditions(2) + minSecondsPayerCancellationNotice(4) = 30B
     *   slot 1: maxInitialTokens(32)
     *   slot 2: maxOngoingTokensPerSecond(32)
     *   slot 3: hash(32)
     *   slot 4+: metadata (dynamic)
     * @param deadline The deadline for accepting these terms
     * @param endsAt The timestamp when the agreement ends
     * @param minSecondsPerCollection The minimum amount of seconds that must pass between collections
     * @param maxSecondsPerCollection The maximum seconds of service that can be collected in a single collection
     * @param conditions Bitfield of agreement conditions (e.g. CONDITION_ELIGIBILITY_CHECK)
     * @param minSecondsPayerCancellationNotice Minimum seconds of notice the payer must give before
     * cancellation takes effect (enforced on cancel and OFFER_TYPE_UPDATE with WITH_NOTICE)
     * @param maxInitialTokens The maximum amount of tokens that can be collected in the first collection
     * @param maxOngoingTokensPerSecond The maximum amount of tokens that can be collected per second
     * @param hash Precomputed EIP-712 hash of the RCA or RCAU that produced these terms
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     */
    struct AgreementTerms {
        uint64 deadline;
        uint64 endsAt;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        uint16 conditions;
        uint32 minSecondsPayerCancellationNotice;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        bytes32 hash;
        bytes metadata;
    }

    /**
     * @notice View of agreement identity, parties, state, temporal info, and collectability.
     * @dev Decouples the public interface from internal storage layout so that storage
     * refactors do not constitute breaking interface changes.
     * @param agreementId The agreement ID
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     * @param dataService The address of the data service
     * @param acceptedAt The timestamp when the agreement was accepted (zero if not yet accepted)
     * @param lastCollectionAt The timestamp of the last collection (zero if never collected)
     * @param collectableUntil The timestamp after which the agreement is no longer collectable
     * @param updateNonce The current nonce for updates (prevents replay attacks)
     * @param state Bitflag state of the agreement (see IAgreementCollector state flags)
     * @param isCollectable Whether the agreement allows collection attempts right now
     * @param collectionSeconds The valid collection duration in seconds (capped at maxSecondsPerCollection)
     */
    struct AgreementData {
        bytes16 agreementId;
        address payer;
        address serviceProvider;
        address dataService;
        uint64 acceptedAt;
        uint64 lastCollectionAt;
        uint64 collectableUntil;
        uint32 updateNonce;
        uint16 state;
        bool isCollectable;
        uint256 collectionSeconds;
    }

    // -- RCA-specific events --

    /**
     * @notice Emitted when an RCA is collected. Links the collection to the agreement.
     * @dev Token amounts and payment breakdown are in GraphPaymentCollected from GraphPayments.
     * @param agreementId The agreement ID
     * @param collectionId The collection ID
     * @param state The agreement state after collection
     */
    event RCACollected(bytes16 indexed agreementId, bytes32 collectionId, uint16 state);
    // solhint-disable-previous-line gas-indexed-events

    // -- RCA-specific errors --

    /**
     * @notice Thrown when calling collect() with a zero collection seconds
     * @param agreementId The agreement ID
     * @param currentTimestamp The current timestamp
     * @param lastCollectionAt The timestamp when the last collection was done
     */
    error ZeroCollectionSeconds(bytes16 agreementId, uint256 currentTimestamp, uint64 lastCollectionAt);

    /**
     * @notice Thrown when calling collect() too soon
     * @param agreementId The agreement ID
     * @param secondsSinceLast Seconds since last collection
     * @param minSeconds Minimum seconds between collections
     */
    error CollectionTooSoon(bytes16 agreementId, uint32 secondsSinceLast, uint32 minSeconds);

    /**
     * @notice Thrown when calling update() with an invalid nonce
     * @param agreementId The agreement ID
     * @param expected The expected nonce
     * @param provided The provided nonce
     */
    error InvalidUpdateNonce(bytes16 agreementId, uint32 expected, uint32 provided);

    /**
     * @notice Thrown when a contract payer's eligibility oracle denies the service provider
     * @param agreementId The agreement ID
     * @param serviceProvider The service provider that is not eligible
     */
    error CollectionNotEligible(bytes16 agreementId, address serviceProvider);

    /**
     * @notice Thrown when the contract approver is not a contract
     * @param approver The address that is not a contract
     */
    error ApproverNotContract(address approver);

    /**
     * @notice Thrown when notice does not satisfy minSecondsPayerCancellationNotice
     * @param agreementId The agreement ID
     * @param minSecondsPayerCancellationNotice The required minimum notice period
     * @param actualSeconds The actual seconds of notice provided
     */
    error InsufficientNotice(bytes16 agreementId, uint32 minSecondsPayerCancellationNotice, uint256 actualSeconds);

    /**
     * @notice Thrown when CONDITION_ELIGIBILITY_CHECK is set but the payer does not
     * advertise IProviderEligibility support via ERC-165.
     * @param payer The payer address that does not support IProviderEligibility
     */
    error EligibilityConditionNotSupported(address payer);

    // -- RCA-specific methods --

    /**
     * @notice Get agreement data for a given agreement ID.
     * @param agreementId The ID of the agreement to retrieve.
     * @return The AgreementData struct containing identity, parties, state, and collectability.
     */
    function getAgreementData(bytes16 agreementId) external view returns (AgreementData memory);

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
