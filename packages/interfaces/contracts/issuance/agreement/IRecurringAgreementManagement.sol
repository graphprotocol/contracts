// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IRecurringCollector } from "../../horizon/IRecurringCollector.sol";

/**
 * @title Interface for agreement lifecycle operations on {RecurringAgreementManager}
 * @author Edge & Node
 * @notice Functions for offering, updating, revoking, canceling, and
 * reconciling managed RCAs (Recurring Collection Agreements).
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRecurringAgreementManagement {
    // -- Events --
    // solhint-disable gas-indexed-events

    /**
     * @notice Emitted when an agreement is offered for escrow management
     * @param agreementId The deterministic agreement ID
     * @param provider The service provider for this agreement
     * @param maxNextClaim The calculated maximum next claim amount
     */
    event AgreementOffered(bytes16 indexed agreementId, address indexed provider, uint256 maxNextClaim);

    /**
     * @notice Emitted when an agreement offer is revoked before acceptance
     * @param agreementId The agreement ID
     * @param provider The provider whose sumMaxNextClaim was reduced
     */
    event OfferRevoked(bytes16 indexed agreementId, address indexed provider);

    /**
     * @notice Emitted when an agreement is canceled via the data service
     * @param agreementId The agreement ID
     * @param provider The provider for this agreement
     */
    event AgreementCanceled(bytes16 indexed agreementId, address indexed provider);

    /**
     * @notice Emitted when an agreement is removed from escrow management
     * @param agreementId The agreement ID being removed
     * @param provider The provider whose sumMaxNextClaim was reduced
     */
    event AgreementRemoved(bytes16 indexed agreementId, address indexed provider);

    /**
     * @notice Emitted when an agreement's max next claim is recalculated
     * @param agreementId The agreement ID
     * @param oldMaxNextClaim The previous max next claim
     * @param newMaxNextClaim The updated max next claim
     */
    event AgreementReconciled(bytes16 indexed agreementId, uint256 oldMaxNextClaim, uint256 newMaxNextClaim);

    /**
     * @notice Emitted when a pending agreement update is offered
     * @param agreementId The agreement ID
     * @param pendingMaxNextClaim The max next claim for the pending update
     * @param updateNonce The RCAU nonce for the pending update
     */
    event AgreementUpdateOffered(bytes16 indexed agreementId, uint256 pendingMaxNextClaim, uint32 updateNonce);

    /**
     * @notice Emitted when a pending agreement update is revoked
     * @param agreementId The agreement ID
     * @param pendingMaxNextClaim The escrow that was freed
     * @param updateNonce The RCAU nonce that was revoked
     */
    event AgreementUpdateRevoked(bytes16 indexed agreementId, uint256 pendingMaxNextClaim, uint32 updateNonce);

    /**
     * @notice Emitted when a (collector, provider) pair is removed from tracking
     * @dev Emitted when the pair has no agreements AND escrow is fully recovered (balance zero).
     * May cascade inline from agreement deletion or be triggered by {reconcileCollectorProvider}.
     * @param collector The collector address
     * @param provider The provider address
     */
    event CollectorProviderRemoved(address indexed collector, address indexed provider);

    /**
     * @notice Emitted when a collector is removed from the global tracking set
     * @dev Emitted when the collector's last provider is removed, cascading from pair removal.
     * @param collector The collector address
     */
    event CollectorRemoved(address indexed collector);

    // solhint-enable gas-indexed-events

    // -- Errors --

    /**
     * @notice Thrown when trying to offer an agreement that is already offered
     * @param agreementId The agreement ID
     */
    error AgreementAlreadyOffered(bytes16 agreementId);

    /**
     * @notice Thrown when trying to operate on an agreement that is not offered
     * @param agreementId The agreement ID
     */
    error AgreementNotOffered(bytes16 agreementId);

    /**
     * @notice Thrown when the RCA payer is not this contract
     * @param payer The payer address in the RCA
     * @param expected The expected payer (this contract)
     */
    error PayerMustBeManager(address payer, address expected);

    /**
     * @notice Thrown when trying to revoke an agreement that is already accepted
     * @param agreementId The agreement ID
     */
    error AgreementAlreadyAccepted(bytes16 agreementId);

    /**
     * @notice Thrown when trying to cancel an agreement that has not been accepted yet
     * @param agreementId The agreement ID
     */
    error AgreementNotAccepted(bytes16 agreementId);

    /**
     * @notice Thrown when the data service address has no deployed code
     * @param dataService The address that was expected to be a contract
     */
    error InvalidDataService(address dataService);

    /// @notice Thrown when the RCA service provider is the zero address
    error ServiceProviderZeroAddress();

    /**
     * @notice Thrown when the data service address does not have DATA_SERVICE_ROLE
     * @param dataService The unauthorized data service address
     */
    error UnauthorizedDataService(address dataService);

    /// @notice Thrown when a collection callback is called by an address other than the agreement's collector
    error OnlyAgreementCollector();

    /**
     * @notice Thrown when the RCAU nonce does not match the expected next update nonce
     * @param agreementId The agreement ID
     * @param expectedNonce The expected nonce (collector's updateNonce + 1)
     * @param actualNonce The nonce provided in the RCAU
     */
    error InvalidUpdateNonce(bytes16 agreementId, uint32 expectedNonce, uint32 actualNonce);

    /**
     * @notice Thrown when the collector address does not have COLLECTOR_ROLE
     * @param collector The unauthorized collector address
     */
    error UnauthorizedCollector(address collector);

    // -- Functions --

    /**
     * @notice Offer an RCA for escrow management. Must be called before
     * the data service accepts the agreement (with empty authData).
     * @dev Calculates max next claim from RCA parameters, stores the authorized hash
     * for the {IAgreementOwner} callback, and deposits into escrow.
     * Requires AGREEMENT_MANAGER_ROLE.
     * @param rca The Recurring Collection Agreement parameters
     * @param collector The RecurringCollector contract to use for this agreement
     * @return agreementId The deterministic agreement ID
     */
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        IRecurringCollector collector
    ) external returns (bytes16 agreementId);

    /**
     * @notice Offer a pending agreement update for escrow management. Must be called
     * before the data service applies the update (with empty authData).
     * @dev Stores the authorized RCAU hash for the {IAgreementOwner} callback and
     * adds the pending update's max next claim to sumMaxNextClaim. Treats the
     * pending update as a separate escrow entry alongside the current agreement.
     * If a previous pending update exists, it is replaced.
     * Requires AGREEMENT_MANAGER_ROLE.
     * @param rcau The Recurring Collection Agreement Update parameters
     * @return agreementId The agreement ID from the RCAU
     */
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external returns (bytes16 agreementId);

    /**
     * @notice Revoke a pending agreement update, freeing its reserved escrow.
     * @dev Requires AGREEMENT_MANAGER_ROLE. Reconciles the agreement first to
     * detect if the update was already applied. If the pending update is still
     * outstanding after reconciliation, clears it and frees the escrow.
     * No-op (returns false) if no pending update exists after reconciliation.
     * @param agreementId The agreement ID whose pending update to revoke
     * @return revoked True if a pending update was cleared by this call
     */
    function revokeAgreementUpdate(bytes16 agreementId) external returns (bool revoked);

    /**
     * @notice Revoke an un-accepted agreement offer. Only for agreements not yet
     * accepted in RecurringCollector.
     * @dev Requires AGREEMENT_MANAGER_ROLE. Clears the agreement tracking and authorized hashes,
     * freeing the reserved escrow. Any pending update is also cleared.
     * No-op (returns true) if the agreement is not tracked.
     * @param agreementId The agreement ID to revoke
     * @return gone True if the agreement is not tracked (whether revoked by this call or already absent)
     */
    function revokeOffer(bytes16 agreementId) external returns (bool gone);

    /**
     * @notice Cancel an accepted agreement by routing through the data service.
     * @dev Requires AGREEMENT_MANAGER_ROLE. Reads agreement state from RecurringCollector:
     * - NotAccepted: reverts (use {revokeOffer} instead)
     * - Accepted: cancels via the data service, then reconciles and updates escrow
     * - Already canceled: idempotent — reconciles and updates escrow without re-canceling
     * After cancellation, call {reconcileAgreement} once the collection window closes.
     * @param agreementId The agreement ID to cancel
     * @return gone True if the agreement is not tracked (already absent); false when
     * the agreement is still tracked (caller should eventually call {reconcileAgreement})
     */
    function cancelAgreement(bytes16 agreementId) external returns (bool gone);

    /**
     * @notice Reconcile a single agreement: re-read on-chain state, recalculate
     * max next claim, update escrow, and delete the agreement if fully settled.
     * @dev Permissionless. Handles all agreement states:
     * - NotAccepted before deadline: keeps pre-offer estimate (returns true)
     * - NotAccepted past deadline: zeroes and deletes (returns false)
     * - Accepted/Canceled: reconciles maxNextClaim, deletes if zero
     * Should be called after collections, cancellations, or agreement updates.
     * @param agreementId The agreement ID to reconcile
     * @return exists True if the agreement is still tracked after this call
     */
    function reconcileAgreement(bytes16 agreementId) external returns (bool exists);

    /**
     * @notice Reconcile a (collector, provider) pair: rebalance escrow, withdraw
     * completed thaws, and remove tracking if fully drained.
     * @dev Permissionless. First updates escrow state (deposit deficit, thaw excess,
     * withdraw completed thaws), then removes pair tracking when both pairAgreementCount
     * and escrow balance are zero. Also serves as the permissionless "poke" to rebalance
     * escrow after {IRecurringEscrowManagement-setEscrowBasis} or {IRecurringEscrowManagement-setTempJit}
     * changes. Returns true if the pair still has agreements or escrow is still thawing.
     * @param collector The collector address
     * @param provider The provider address
     * @return exists True if the pair is still tracked after this call
     */
    function reconcileCollectorProvider(address collector, address provider) external returns (bool exists);
}
