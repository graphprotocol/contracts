// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

import { IRecurringCollector } from "../../horizon/IRecurringCollector.sol";

/**
 * @title Interface for the {ServiceAgreementManager} contract
 * @author Edge & Node
 * @notice Manages escrow funding for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. Tracks the maximum possible next claim for each managed
 * RCA per provider and ensures PaymentsEscrow is always funded to cover those maximums.
 *
 * One escrow per (ServiceAgreementManager, RecurringCollector, provider) covering all RCAs for
 * that provider managed by this contract.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IServiceAgreementManager {
    // -- Structs --

    /**
     * @notice Tracked state for a managed agreement
     * @dev An agreement is considered tracked when `provider != address(0)`.
     * @param provider The service provider for this agreement
     * @param deadline The RCA deadline for acceptance (used to detect expired offers)
     * @param dataService The data service address for this agreement
     * @param pendingUpdateNonce The RCAU nonce for the pending update (0 means no pending)
     * @param maxNextClaim The current maximum tokens claimable in the next collection
     * @param pendingUpdateMaxNextClaim Max next claim for an offered-but-not-yet-applied update
     * @param agreementHash The RCA hash stored for cleanup of authorizedHashes on deletion
     * @param pendingUpdateHash The RCAU hash stored for cleanup of authorizedHashes on deletion
     */
    struct AgreementInfo {
        address provider;
        uint64 deadline;
        address dataService;
        uint32 pendingUpdateNonce;
        uint256 maxNextClaim;
        uint256 pendingUpdateMaxNextClaim;
        bytes32 agreementHash;
        bytes32 pendingUpdateHash;
    }

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
     * @param provider The provider whose required escrow was reduced
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
     * @param provider The provider whose required escrow was reduced
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
     * @notice Emitted when escrow is funded for a provider
     * @param provider The provider whose escrow was funded
     * @param collector The collector address for the escrow account
     * @param deposited The amount deposited
     */
    event EscrowFunded(address indexed provider, address indexed collector, uint256 deposited);

    /**
     * @notice Emitted when thawed escrow tokens are withdrawn
     * @param provider The provider whose escrow was withdrawn
     * @param collector The collector address for the escrow account
     * @param tokens The amount of tokens withdrawn
     */
    event EscrowWithdrawn(address indexed provider, address indexed collector, uint256 tokens);

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
     * @notice Thrown when trying to remove an agreement that is still claimable
     * @param agreementId The agreement ID
     * @param maxNextClaim The remaining max next claim
     */
    error AgreementStillClaimable(bytes16 agreementId, uint256 maxNextClaim);

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

    /// @notice Thrown when the RCA data service is the zero address
    error DataServiceZeroAddress();

    // -- Core Functions --

    /**
     * @notice Offer an RCA for escrow management. Must be called before
     * the data service accepts the agreement (with empty authData).
     * @dev Calculates max next claim from RCA parameters, stores the authorized hash
     * for the {IContractApprover} callback, and funds the escrow.
     * @param rca The Recurring Collection Agreement parameters
     * @return agreementId The deterministic agreement ID
     */
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca
    ) external returns (bytes16 agreementId);

    /**
     * @notice Offer a pending agreement update for escrow management. Must be called
     * before the data service applies the update (with empty authData).
     * @dev Stores the authorized RCAU hash for the {IContractApprover} callback and
     * adds the pending update's max next claim to the required escrow. Treats the
     * pending update as a separate escrow entry alongside the current agreement.
     * If a previous pending update exists, it is replaced.
     * @param rcau The Recurring Collection Agreement Update parameters
     * @return agreementId The agreement ID from the RCAU
     */
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external returns (bytes16 agreementId);

    /**
     * @notice Revoke an un-accepted agreement offer. Only for agreements not yet
     * accepted in RecurringCollector.
     * @dev Requires OPERATOR_ROLE. Clears the agreement tracking and authorized hashes,
     * freeing the reserved escrow. Any pending update is also cleared.
     * @param agreementId The agreement ID to revoke
     */
    function revokeOffer(bytes16 agreementId) external;

    /**
     * @notice Cancel an accepted agreement by routing through the data service.
     * @dev Requires OPERATOR_ROLE. Reads agreement state from RecurringCollector:
     * - NotAccepted: reverts (use {revokeOffer} instead)
     * - Accepted: cancels via the data service, then reconciles and funds escrow
     * - Already canceled: idempotent — reconciles and funds escrow without re-canceling
     * After cancellation, call {removeAgreement} once the collection window closes.
     * @param agreementId The agreement ID to cancel
     */
    function cancelAgreement(bytes16 agreementId) external;

    /**
     * @notice Remove a fully expired agreement from tracking.
     * @dev Permissionless. Only succeeds when the agreement's max next claim is 0 (no more
     * collections possible). This covers: CanceledByServiceProvider (immediate),
     * CanceledByPayer (after window expires), active agreements past endsAt, and
     * NotAccepted offers past their deadline.
     * @param agreementId The agreement ID to remove
     */
    function removeAgreement(bytes16 agreementId) external;

    /**
     * @notice Reconcile a single agreement. Re-reads agreement state from
     * RecurringCollector, recalculates max next claim, and tops up escrow.
     * @dev Permissionless. This is the primary reconciliation function — gas-predictable,
     * per-agreement. Skips if agreement is not yet accepted in RecurringCollector.
     * Should be called after collections, cancellations, or agreement updates.
     * @param agreementId The agreement ID to reconcile
     */
    function reconcileAgreement(bytes16 agreementId) external;

    /**
     * @notice Reconcile all agreements for a provider (convenience function).
     * @dev Permissionless. Iterates all tracked agreements — O(n) gas,
     * may hit gas limits with many agreements. Prefer reconcileAgreement for individual
     * updates, or reconcileBatch for controlled batching.
     * @param provider The provider to reconcile
     */
    function reconcile(address provider) external;

    /**
     * @notice Reconcile a batch of agreements (operator-controlled batching).
     * @dev Permissionless. Allows callers to control gas usage by choosing which
     * agreements to reconcile in a single transaction.
     * @param agreementIds The agreement IDs to reconcile
     */
    function reconcileBatch(bytes16[] calldata agreementIds) external;

    /**
     * @notice Update escrow state for a provider: withdraw completed thaws, fund any deficit,
     * and thaw excess balance.
     * @dev Permissionless. Three-phase operation:
     * - Phase 1: If a previous thaw has completed, withdraws tokens back to this contract
     * - Phase 2a (deficit): If balance < required, cancels any thaw and deposits to cover
     * - Phase 2b (excess): If balance > required, starts a thaw for the excess (only when
     *   no thaw is already in progress) or partially cancels an existing thaw if too much
     *   is being thawed
     * Works regardless of whether the provider has active agreements.
     * @param provider The provider to update escrow for
     */
    function updateEscrow(address provider) external;

    // -- View Functions --

    /**
     * @notice Get the total required escrow for a provider
     * @param provider The provider address
     * @return The sum of max next claims for all managed agreements for this provider
     */
    function getRequiredEscrow(address provider) external view returns (uint256);

    /**
     * @notice Get the current escrow deficit for a provider
     * @dev Returns 0 if escrow is fully funded or over-funded.
     * @param provider The provider address
     * @return The deficit amount (required - current balance), or 0 if no deficit
     */
    function getDeficit(address provider) external view returns (uint256);

    /**
     * @notice Get the max next claim for a specific agreement
     * @param agreementId The agreement ID
     * @return The current max next claim stored for this agreement
     */
    function getAgreementMaxNextClaim(bytes16 agreementId) external view returns (uint256);

    /**
     * @notice Get the full tracked state for a specific agreement
     * @param agreementId The agreement ID
     * @return The agreement info struct (all fields zero if not tracked)
     */
    function getAgreementInfo(bytes16 agreementId) external view returns (AgreementInfo memory);

    /**
     * @notice Get the number of managed agreements for a provider
     * @param provider The provider address
     * @return The count of tracked agreements
     */
    function getProviderAgreementCount(address provider) external view returns (uint256);

    /**
     * @notice Get all managed agreement IDs for a provider
     * @dev Returns the full set of tracked agreement IDs. May be expensive for providers
     * with many agreements — prefer {getProviderAgreementCount} for on-chain use.
     * @param provider The provider address
     * @return The array of agreement IDs
     */
    function getProviderAgreements(address provider) external view returns (bytes16[] memory);
}
