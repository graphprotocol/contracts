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
/// ORed into returned state by getAgreementDetails for pending versions (index 1).
uint16 constant UPDATE = 128;

// -- Togglable option flags (set via accept options parameter) --

/// @dev Provider opts in to automatic update on final collect
uint16 constant AUTO_UPDATE = 256;

// -- Lifecycle flags (set by the collector during auto-update, clearable) --

/// @dev Active terms were promoted via auto-update (not explicit provider accept)
uint16 constant AUTO_UPDATED = 512;

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
     * @notice Agreement details: participants, version hash, and state flags.
     * Returned by {offer} and {getAgreementDetails}.
     * @param agreementId The agreement ID
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param versionHash The EIP-712 hash of the terms at the requested version
     * @param state Agreement state flags, with UPDATE set when applicable
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
     * @param offerType The type of offer (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE)
     * @param data ABI-encoded offer data
     * @param options Bitmask of offer options
     * @return Agreement details including participants and version hash
     */
    function offer(uint8 offerType, bytes calldata data, uint16 options) external returns (AgreementDetails memory);

    /**
     * @notice Cancel an agreement or revoke a pending update, determined by termsHash.
     * @param agreementId The agreement's ID.
     * @param termsHash EIP-712 hash identifying which terms to cancel (active or pending).
     * @param options Bitmask — SCOPE_ACTIVE (1) targets active terms, SCOPE_PENDING (2) targets pending offers.
     */
    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 options) external;

    /**
     * @notice Get agreement details at a given version index.
     * @param agreementId The ID of the agreement
     * @param index The zero-based version index
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
     * @notice Original offer for a given version, enabling independent access and hash verification.
     * @dev Returns the offer type (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE) and the ABI-encoded
     * original struct. Callers can decode and hash to verify the stored version hash.
     * @param agreementId The ID of the agreement
     * @param index The zero-based version index
     * @return offerType OFFER_TYPE_NEW, OFFER_TYPE_UPDATE, or OFFER_TYPE_NONE when no offer is stored
     * @return offerData ABI-encoded original offer struct, or empty when offerType is OFFER_TYPE_NONE
     */
    function getAgreementOfferAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (uint8 offerType, bytes memory offerData);
}
