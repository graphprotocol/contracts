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
}
