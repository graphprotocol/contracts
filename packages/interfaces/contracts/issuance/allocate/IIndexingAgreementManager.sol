// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

import { IRecurringCollector } from "../../horizon/IRecurringCollector.sol";

/**
 * @title Interface for the {IndexingAgreementManager} contract
 * @author Edge & Node
 * @notice Manages escrow funding for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. Tracks the maximum possible next claim for each managed
 * RCA per indexer and ensures PaymentsEscrow is always funded to cover those maximums.
 *
 * One escrow per (IndexingAgreementManager, RecurringCollector, indexer) covering all RCAs for
 * that indexer managed by this contract.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IIndexingAgreementManager {
    // -- Structs --

    /**
     * @notice Tracked state for a managed agreement
     * @param indexer The service provider (indexer) for this agreement
     * @param deadline The RCA deadline for acceptance (used to detect expired offers)
     * @param exists Whether this agreement is actively tracked
     * @param dataService The data service address for this agreement
     * @param pendingUpdateNonce The RCAU nonce for the pending update (0 means no pending)
     * @param maxNextClaim The current maximum tokens claimable in the next collection
     * @param pendingUpdateMaxNextClaim Max next claim for an offered-but-not-yet-applied update
     * @param agreementHash The RCA hash stored for cleanup of authorizedHashes on deletion
     * @param pendingUpdateHash The RCAU hash stored for cleanup of authorizedHashes on deletion
     */
    struct AgreementInfo {
        address indexer;
        uint64 deadline;
        bool exists;
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
     * @param indexer The indexer (service provider) for this agreement
     * @param maxNextClaim The calculated maximum next claim amount
     */
    event AgreementOffered(bytes16 indexed agreementId, address indexed indexer, uint256 maxNextClaim);

    /**
     * @notice Emitted when an agreement offer is revoked before acceptance
     * @param agreementId The agreement ID
     * @param indexer The indexer whose required escrow was reduced
     */
    event OfferRevoked(bytes16 indexed agreementId, address indexed indexer);

    /**
     * @notice Emitted when an agreement is canceled via the data service
     * @param agreementId The agreement ID
     * @param indexer The indexer for this agreement
     */
    event AgreementCanceled(bytes16 indexed agreementId, address indexed indexer);

    /**
     * @notice Emitted when an agreement is removed from escrow management
     * @param agreementId The agreement ID being removed
     * @param indexer The indexer whose required escrow was reduced
     */
    event AgreementRemoved(bytes16 indexed agreementId, address indexed indexer);

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
     * @notice Emitted when escrow is funded for an indexer
     * @param indexer The indexer whose escrow was funded
     * @param requiredEscrow The total required escrow for the indexer
     * @param currentBalance The escrow balance after funding
     * @param deposited The amount deposited in this transaction
     */
    event EscrowFunded(address indexed indexer, uint256 requiredEscrow, uint256 currentBalance, uint256 deposited);

    /**
     * @notice Emitted when escrow tokens are thawed for withdrawal
     * @param indexer The indexer whose escrow is being thawed
     * @param tokens The amount of tokens being thawed
     */
    event EscrowThawed(address indexed indexer, uint256 tokens);

    /**
     * @notice Emitted when thawed escrow tokens are withdrawn
     * @param indexer The indexer whose escrow was withdrawn
     */
    event EscrowWithdrawn(address indexed indexer);

    // solhint-enable gas-indexed-events

    // -- Errors --

    /**
     * @notice Thrown when trying to offer an agreement that is already offered
     * @param agreementId The agreement ID
     */
    error IndexingAgreementManagerAgreementAlreadyOffered(bytes16 agreementId);

    /**
     * @notice Thrown when trying to operate on an agreement that is not offered
     * @param agreementId The agreement ID
     */
    error IndexingAgreementManagerAgreementNotOffered(bytes16 agreementId);

    /**
     * @notice Thrown when the RCA payer is not this contract
     * @param payer The payer address in the RCA
     * @param expected The expected payer (this contract)
     */
    error IndexingAgreementManagerPayerMismatch(address payer, address expected);

    /**
     * @notice Thrown when trying to remove an agreement that is still claimable
     * @param agreementId The agreement ID
     * @param maxNextClaim The remaining max next claim
     */
    error IndexingAgreementManagerAgreementStillClaimable(bytes16 agreementId, uint256 maxNextClaim);

    /**
     * @notice Thrown when trying to revoke an agreement that is already accepted
     * @param agreementId The agreement ID
     */
    error IndexingAgreementManagerAgreementAlreadyAccepted(bytes16 agreementId);

    /**
     * @notice Thrown when trying to cancel an agreement that has not been accepted yet
     * @param agreementId The agreement ID
     */
    error IndexingAgreementManagerAgreementNotAccepted(bytes16 agreementId);

    /**
     * @notice Thrown when an agreement hash is not authorized
     * @param agreementHash The hash that was not authorized
     */
    error IndexingAgreementManagerAgreementNotAuthorized(bytes32 agreementHash);

    /**
     * @notice Thrown when the data service address has no deployed code
     * @param dataService The address that was expected to be a contract
     */
    error IndexingAgreementManagerInvalidDataService(address dataService);

    /**
     * @notice Thrown when maintain is called but the indexer still has agreements
     * @param indexer The indexer address
     */
    error IndexingAgreementManagerStillHasAgreements(address indexer);

    /**
     * @notice Thrown when an RCA has a zero-address service provider or data service
     * @param field The name of the invalid field
     */
    error IndexingAgreementManagerInvalidRCAField(string field);

    // -- Core Functions --

    /**
     * @notice Offer an RCA for escrow management. Must be called before
     * {SubgraphService.acceptUnsignedIndexingAgreement}.
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
     * before {SubgraphService.updateUnsignedIndexingAgreement}.
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
     * @notice Reconcile all agreements for an indexer (convenience function).
     * @dev Permissionless. Iterates all tracked agreements for the indexer — O(n) gas,
     * may hit gas limits with many agreements. Prefer reconcileAgreement for individual
     * updates, or reconcileBatch for controlled batching.
     * @param indexer The indexer to reconcile
     */
    function reconcile(address indexer) external;

    /**
     * @notice Reconcile a batch of agreements (operator-controlled batching).
     * @dev Permissionless. Allows callers to control gas usage by choosing which
     * agreements to reconcile in a single transaction.
     * @param agreementIds The agreement IDs to reconcile
     */
    function reconcileBatch(bytes16[] calldata agreementIds) external;

    /**
     * @notice Maintain escrow for an indexer with no remaining agreements.
     * @dev Permissionless. Two-phase operation:
     * - If a previous thaw has completed: withdraws tokens back to this contract
     * - If escrow balance remains: initiates a thaw for the available balance
     * Only operates when the indexer has zero tracked agreements. Guards against
     * reducing an in-progress thaw.
     * @param indexer The indexer to maintain
     */
    function maintain(address indexer) external;

    // -- View Functions --

    /**
     * @notice Get the total required escrow for an indexer
     * @param indexer The indexer address
     * @return The sum of max next claims for all managed agreements for this indexer
     */
    function getRequiredEscrow(address indexer) external view returns (uint256);

    /**
     * @notice Get the current escrow deficit for an indexer
     * @dev Returns 0 if escrow is fully funded or over-funded.
     * @param indexer The indexer address
     * @return The deficit amount (required - current balance), or 0 if no deficit
     */
    function getDeficit(address indexer) external view returns (uint256);

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
     * @notice Get the number of managed agreements for an indexer
     * @param indexer The indexer address
     * @return The count of tracked agreements
     */
    function getIndexerAgreementCount(address indexer) external view returns (uint256);

    /**
     * @notice Get all managed agreement IDs for an indexer
     * @dev Returns the full set of tracked agreement IDs. May be expensive for indexers
     * with many agreements — prefer {getIndexerAgreementCount} for on-chain use.
     * @param indexer The indexer address
     * @return The array of agreement IDs
     */
    function getIndexerAgreements(address indexer) external view returns (bytes16[] memory);
}
