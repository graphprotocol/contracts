// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";

// -- State flags for AgreementDetails --
// Describe the queried version in context of its agreement; returned by both
// offer() and getAgreementDetails(). See AgreementDetails.state NatSpec.

/// @dev Offer exists in storage. Implied by ACCEPTED.
uint16 constant REGISTERED = 1;
/// @dev Provider accepted terms. Always returned with REGISTERED set (accepted terms were stored).
uint16 constant ACCEPTED = 2;
/// @dev The agreement's collection window has been truncated (e.g. by cancellation).
/// Paired with a BY_* flag identifying the origin.
uint16 constant NOTICE_GIVEN = 4;
/// @dev Nothing to collect under this version's terms (per-version: scoped to active claim
/// for VERSION_CURRENT, pending claim for VERSION_NEXT).
uint16 constant SETTLED = 8;

// -- Who-initiated flags (meaningful when NOTICE_GIVEN is set) --

/// @dev NOTICE_GIVEN originated from the payer.
uint16 constant BY_PAYER = 16;
/// @dev NOTICE_GIVEN originated from the service provider.
uint16 constant BY_PROVIDER = 32;

// -- Update-origin flag --

/// @dev This version's terms originated from an update, not the initial agreement offer.
/// Describes the version's provenance; set wherever the update-derived version is returned.
uint16 constant UPDATE = 128;

// -- Offer type constants --

/// @dev No stored offer — sentinel returned by {IAgreementCollector.getAgreementOfferAt}
/// when the requested version has no offer data.
uint8 constant OFFER_TYPE_NONE = 0;
/// @dev Create a new agreement
uint8 constant OFFER_TYPE_NEW = 1;
/// @dev Update an existing agreement
uint8 constant OFFER_TYPE_UPDATE = 2;

// -- Cancel scope constants --

/// @dev Cancel targets active terms
uint8 constant SCOPE_ACTIVE = 1;
/// @dev Cancel targets pending offers
uint8 constant SCOPE_PENDING = 2;
/// @dev Cancel targets signed offers
uint8 constant SCOPE_SIGNED = 4;

// -- Version indices (shared by getAgreementDetails and getAgreementOfferAt) --
//
// Versions are enumerated starting at 0. Implementations may expose any number of versions;
// callers iterate until an empty result signals no further versions. These named aliases
// cover the two versions every collector is expected to expose.

/// @dev The currently-active version: the accepted terms if the agreement is accepted,
/// otherwise the pre-acceptance offer (if any). Empty when no agreement or offer exists.
uint256 constant VERSION_CURRENT = 0;
/// @dev The next queued version: a pending update offer waiting to be accepted.
/// Empty when no queued update exists.
uint256 constant VERSION_NEXT = 1;

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
     * @notice Agreement details: participants, version hash, and state flags.
     * Returned by {offer} and {getAgreementDetails}.
     *
     * The `state` field describes the version identified by `versionHash` in the
     * context of its agreement. Version-specific flags (REGISTERED, ACCEPTED,
     * UPDATE, SETTLED) are set only when they apply to that specific version;
     * agreement-wide flags (NOTICE_GIVEN, BY_PAYER, BY_PROVIDER) reflect the
     * current agreement state. Identical semantics whether returned by {offer}
     * or {getAgreementDetails} — the returned flags always describe the queried
     * version.
     *
     * @param agreementId The agreement ID
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param versionHash The EIP-712 hash of the terms at the requested version
     * @param state State flags describing the queried version in context of its agreement
     */
    // solhint-disable-next-line gas-struct-packing
    struct AgreementDetails {
        bytes16 agreementId;
        address payer;
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
     * @dev Returns {AgreementDetails} for the just-stored offer. The `state` field
     * describes that version in context of its agreement (see {AgreementDetails}):
     * version-specific flags (REGISTERED, ACCEPTED, UPDATE, SETTLED) are set when
     * they apply to the offered version; agreement-wide flags (NOTICE_GIVEN, BY_*)
     * reflect current agreement state.
     * @param offerType The type of offer (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE)
     * @param data ABI-encoded offer data
     * @param options Bitmask reserved for implementation-specific options; pass 0 when none apply.
     * No flags are defined at the interface level.
     * @return Agreement details including participants and version hash
     */
    function offer(uint8 offerType, bytes calldata data, uint16 options) external returns (AgreementDetails memory);

    /**
     * @notice Cancel an agreement, revoke a pending offer, or invalidate a signed offer.
     * @dev Scopes can be combined. SCOPE_SIGNED is self-authenticating (keyed by msg.sender);
     * SCOPE_PENDING and SCOPE_ACTIVE require payer authorization and no-op if nothing exists on-chain.
     * @param agreementId The agreement's ID. For SCOPE_SIGNED, only blocks accept/update when
     * the agreementId matches; passing bytes16(0) undoes a previous cancellation.
     * @param termsHash EIP-712 hash identifying which terms to cancel.
     * @param options Bitmask — SCOPE_ACTIVE (1) active terms, SCOPE_PENDING (2) pending offers,
     * SCOPE_SIGNED (4) signed offers.
     */
    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 options) external;

    /**
     * @notice Get agreement details at a given version index.
     * @dev Versions are enumerated from 0. VERSION_CURRENT is the active version (or
     * pre-acceptance offer); VERSION_NEXT is the queued pending update, if any. Empty
     * details are returned when no version exists at the requested index — callers can
     * iterate versions until reaching an empty result.
     * @param agreementId The ID of the agreement
     * @param index Version index (VERSION_CURRENT, VERSION_NEXT, or higher if the implementation supports more)
     * @return Agreement details including participants, version hash, and state flags
     */
    function getAgreementDetails(bytes16 agreementId, uint256 index) external view returns (AgreementDetails memory);

    /**
     * @notice Get the maximum tokens collectable for an agreement, scoped by active and/or pending terms.
     * @param agreementId The ID of the agreement
     * @param scope Bitmask: 1 = active terms, 2 = pending terms, 3 = max of both
     * @return The maximum tokens that could be collected under the requested scope
     */
    function getMaxNextClaim(bytes16 agreementId, uint8 scope) external view returns (uint256);

    /**
     * @notice Convenience overload: returns max of both active and pending terms.
     * @param agreementId The ID of the agreement
     * @return The maximum tokens that could be collected
     */
    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256);

    /**
     * @notice Original offer data for a given version index, enabling independent access and hash verification.
     * @dev Returns the offer type and the ABI-encoded original struct so callers can decode
     * and rehash to verify the version hash returned by getAgreementDetails. Version semantics
     * mirror getAgreementDetails, but empty data is returned when the version's offer was not
     * stored (e.g. signed acceptance without a prior offer(), or overwritten by a later update).
     * @param agreementId The ID of the agreement
     * @param index Version index (VERSION_CURRENT, VERSION_NEXT, or higher if supported)
     * @return offerType OFFER_TYPE_NEW, OFFER_TYPE_UPDATE, or OFFER_TYPE_NONE when no offer is stored
     * @return offerData ABI-encoded original offer struct, or empty when offerType is OFFER_TYPE_NONE
     */
    function getAgreementOfferAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (uint8 offerType, bytes memory offerData);
}
