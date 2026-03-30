// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";

// -- Agreement state flags --
// REGISTERED, ACCEPTED are monotonic (once set, never cleared).
// All other flags are clearable — cleared when pending terms are accepted.

/// @dev Offer exists in storage
uint16 constant REGISTERED = 1;
/// @dev Provider accepted terms
uint16 constant ACCEPTED = 2;
/// @dev collectableUntil has been reduced, collection capped (clearable)
uint16 constant NOTICE_GIVEN = 4;
/// @dev Nothing to collect in current state (clearable — cleared on new terms promotion)
uint16 constant SETTLED = 8;

// -- Who-initiated flags (clearable, meaningful when NOTICE_GIVEN is set) --

/// @dev Notice given by payer
uint16 constant BY_PAYER = 16;
/// @dev Notice given by provider (forfeit — immediate SETTLED)
uint16 constant BY_PROVIDER = 32;
/// @dev Notice given by data service
uint16 constant BY_DATA_SERVICE = 64;

// -- Update-origin flag --

/// @dev Terms originated from an RCAU (update), not the initial RCA.
/// Set on agreement state when active terms come from an accepted or pre-acceptance update.
/// ORed into returned state by getAgreementVersionAt for pending versions (index 1).
uint16 constant UPDATE = 128;

// -- Togglable option flags (set via accept options parameter) --

/// @dev Provider opts in to automatic update on final collect
uint16 constant AUTO_UPDATE = 256;

// -- Lifecycle flags (set by the collector during auto-update, clearable) --

/// @dev Active terms were promoted via auto-update (not explicit provider accept)
uint16 constant AUTO_UPDATED = 512;

// -- Offer type constants --

/// @dev Create a new agreement
uint8 constant OFFER_TYPE_NEW = 0;
/// @dev Update an existing agreement
uint8 constant OFFER_TYPE_UPDATE = 1;

// -- Offer option constants (for unsigned offer path) --

/// @dev Reduce collectableUntil and set NOTICE_GIVEN | BY_PAYER on the agreement
uint16 constant WITH_NOTICE = 1;
/// @dev Revert if the targeted version has already been accepted
uint16 constant IF_NOT_ACCEPTED = 2;

/**
 * @title Base interface for agreement-based payment collectors
 * @notice Base interface for agreement-based payment collectors.
 * @author Edge & Node
 * @dev Defines the generic lifecycle operations shared by all agreement-based
 * collectors. Concrete collectors (e.g. {IRecurringCollector}) extend this
 * with agreement-type-specific structures, methods, and validation.
 * Inherits {IPaymentsCollector} for the collect() entry point.
 * Does not prescribe pausability or signer authorization — those are
 * implementation concerns for concrete collectors.
 */
interface IAgreementCollector is IPaymentsCollector {
    // -- Structs --

    /**
     * @notice Snapshot of an agreement's version hash and state at a given index.
     * @param agreementId The agreement ID
     * @param versionHash The EIP-712 hash of the terms at that index
     * @param state The agreement state flags, with UPDATE set when applicable
     */
    struct AgreementVersion {
        bytes16 agreementId;
        bytes32 versionHash;
        uint16 state;
    }

    /**
     * @notice Return value for opaque offer overloads.
     * @param agreementId The deterministically generated agreement ID
     * @param dataService The data service address from the decoded agreement
     * @param serviceProvider The service provider address from the decoded agreement
     * @param versionHash The EIP-712 hash of the terms that were stored
     * @param state Agreement state flags, includes UPDATE when the version is pending
     */
    // solhint-disable-next-line gas-struct-packing
    struct OfferResult {
        bytes16 agreementId;
        address dataService;
        address serviceProvider;
        bytes32 versionHash;
        uint16 state;
    }

    // -- Enums --

    /// @dev The stage of a payer callback
    enum PayerCallbackStage {
        EligibilityCheck,
        BeforeCollection,
        AfterCollection
    }

    // -- Methods --

    /**
     * @notice Offer a new agreement or update an existing one.
     * @param offerType The type of offer (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE)
     * @param data ABI-encoded offer data
     * @param options Bitmask of offer options (e.g. WITH_NOTICE)
     * @return The offer result containing agreementId, dataService, and serviceProvider
     */
    function offer(uint8 offerType, bytes calldata data, uint16 options) external returns (OfferResult memory);

    /**
     * @notice Accept a previously offered agreement or pending update by its ID and hash.
     * @param agreementId The ID of the agreement to accept
     * @param agreementHash EIP-712 hash the service provider expects to accept
     * @param extraData Opaque data forwarded to the data service callback
     * @param options Bitmask of agreement options (e.g. AUTO_UPDATE)
     */
    function accept(bytes16 agreementId, bytes32 agreementHash, bytes calldata extraData, uint16 options) external;

    /**
     * @notice Cancel an agreement or revoke a pending update, determined by termsHash.
     * @param agreementId The agreement's ID.
     * @param termsHash EIP-712 hash identifying which terms to cancel (active or pending).
     * @param options Bitmask — IF_NOT_ACCEPTED reverts if the targeted version was already accepted.
     */
    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 options) external;

    /**
     * @notice Get the version hash and state at a given index for an agreement.
     * @param agreementId The ID of the agreement
     * @param index The zero-based version index
     * @return The AgreementVersion containing versionHash and state
     */
    function getAgreementVersionAt(bytes16 agreementId, uint256 index) external view returns (AgreementVersion memory);

    /**
     * @notice Get the number of term versions stored for an agreement.
     * @param agreementId The ID of the agreement
     * @return The number of stored term versions
     */
    function getAgreementVersionCount(bytes16 agreementId) external view returns (uint256);

    /**
     * @notice Get the maximum tokens collectable for an agreement, scoped by active and/or pending terms.
     * @param agreementId The ID of the agreement
     * @param claimScope Bitmask: 1 = active terms, 2 = pending terms, 3 = max of both
     * @return The maximum tokens that could be collected under the requested scope
     */
    function getMaxNextClaim(bytes16 agreementId, uint8 claimScope) external view returns (uint256);

    /**
     * @notice Convenience overload: returns max of both active and pending terms.
     * @param agreementId The ID of the agreement
     * @return The maximum tokens that could be collected
     */
    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256);

    /**
     * @notice Reconstruct the original offer for a given version, enabling independent hash verification.
     * @dev Returns the offer type (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE) and the ABI-encoded
     * original struct. Callers can decode and hash to verify the stored version hash.
     * @param agreementId The ID of the agreement
     * @param index The zero-based version index
     * @return offerType OFFER_TYPE_NEW (0) or OFFER_TYPE_UPDATE (1)
     * @return offerData ABI-encoded original offer struct
     */
    function getAgreementOfferAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (uint8 offerType, bytes memory offerData);
}
