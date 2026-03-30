// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { IAgreementCollector } from "../../horizon/IAgreementCollector.sol";

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
     * @notice Emitted when an agreement is discovered and registered for escrow management.
     * @param agreementId The deterministic agreement ID
     * @param collector The collector contract address
     * @param dataService The data service address
     * @param provider The service provider for this agreement
     */
    event AgreementAdded(
        bytes16 indexed agreementId,
        address indexed collector,
        address dataService,
        address indexed provider
    );

    /**
     * @notice Emitted when an agreement callback is ignored because it does not belong to this manager.
     * @dev Useful for debugging missed agreements.
     * @param agreementId The agreement ID
     * @param collector The collector that sent the callback
     * @param reason The rejection reason
     */
    event AgreementRejected(bytes16 indexed agreementId, address indexed collector, AgreementRejectionReason reason);

    /// @notice Why an agreement was not tracked by this manager.
    enum AgreementRejectionReason {
        UnauthorizedCollector,
        UnknownAgreement,
        PayerMismatch,
        UnauthorizedDataService
    }

    /**
     * @notice Emitted when an agreement is removed from escrow management
     * @param agreementId The agreement ID being removed
     */
    event AgreementRemoved(bytes16 indexed agreementId);

    /**
     * @notice Emitted when an agreement's max next claim is recalculated
     * @param agreementId The agreement ID
     * @param oldMaxNextClaim The previous max next claim
     * @param newMaxNextClaim The updated max next claim
     */
    event AgreementReconciled(bytes16 indexed agreementId, uint256 oldMaxNextClaim, uint256 newMaxNextClaim);

    /**
     * @notice Emitted when a (collector, provider) pair is removed from tracking
     * @dev Emitted when the pair has no agreements AND escrow is fully recovered (balance zero).
     * May cascade inline from agreement deletion or be triggered by {reconcileProvider}.
     * @param collector The collector address
     * @param provider The provider address
     */
    event ProviderRemoved(address indexed collector, address indexed provider);

    /**
     * @notice Emitted when a collector is removed from the global tracking set
     * @dev Emitted when the collector's last provider is removed, cascading from pair removal.
     * @param collector The collector address
     */
    event CollectorRemoved(address indexed collector);

    // solhint-enable gas-indexed-events

    // -- Errors --

    /**
     * @notice Thrown when re-offering an agreement with a different service provider
     * @param agreementId The agreement ID
     */
    error ServiceProviderMismatch(bytes16 agreementId);

    /**
     * @notice Thrown when the RCA payer is not this contract
     * @param payer The payer address in the RCA
     * @param expected The expected payer (this contract)
     */
    error PayerMustBeManager(address payer, address expected);

    /// @notice Thrown when the RCA service provider is the zero address
    error ServiceProviderZeroAddress();

    /**
     * @notice Thrown when the data service address does not have DATA_SERVICE_ROLE
     * @param dataService The unauthorized data service address
     */
    error UnauthorizedDataService(address dataService);

    /**
     * @notice Thrown when the collector address does not have COLLECTOR_ROLE
     * @param collector The unauthorized collector address
     */
    error UnauthorizedCollector(address collector);

    // -- Functions --

    /**
     * @notice Offer an RCA for escrow management.
     * @dev Forwards opaque offer data to the collector, which decodes and validates it,
     * then reconciles agreement tracking and escrow locally after the call returns.
     * The collector does not callback to `msg.sender` — see RecurringCollector callback model.
     * Requires AGREEMENT_MANAGER_ROLE.
     * @param collector The RecurringCollector contract to use for this agreement
     * @param offerType The offer type (OFFER_TYPE_NEW or OFFER_TYPE_UPDATE)
     * @param offerData Opaque ABI-encoded agreement data forwarded to the collector
     * @return agreementId The deterministic agreement ID
     */
    function offerAgreement(
        IAgreementCollector collector,
        uint8 offerType,
        bytes calldata offerData
    ) external returns (bytes16 agreementId);

    /**
     * @notice Cancel an agreement or pending update by routing through the collector.
     * @dev Requires AGREEMENT_MANAGER_ROLE. Forwards the terms hash to the collector's
     * cancel function, then reconciles locally after the call returns. The collector does
     * not callback to `msg.sender` — see RecurringCollector callback model.
     * @param collector The collector contract address for this agreement
     * @param agreementId The agreement ID to cancel
     * @param versionHash The terms hash to cancel (activeTerms.hash or pendingTerms.hash)
     * @param options Bitmask — IF_NOT_ACCEPTED reverts if the targeted version was already accepted.
     */
    function cancelAgreement(
        IAgreementCollector collector,
        bytes16 agreementId,
        bytes32 versionHash,
        uint16 options
    ) external;

    /**
     * @notice Reconcile a single agreement: re-read on-chain state, recalculate
     * max next claim, update escrow, and delete the agreement if fully settled.
     * @dev Permissionless. Handles all agreement states:
     * - NotAccepted before deadline: keeps pre-offer estimate (returns true)
     * - NotAccepted past deadline: zeroes and deletes (returns false)
     * - Accepted/Canceled: reconciles maxNextClaim, deletes if zero
     * Should be called after collections, cancellations, or agreement updates.
     * @param collector The collector contract address for this agreement
     * @param agreementId The agreement ID to reconcile
     * @return exists True if the agreement is still tracked after this call
     */
    function reconcileAgreement(IAgreementCollector collector, bytes16 agreementId) external returns (bool exists);

    /**
     * @notice Force-remove a tracked agreement whose collector is unresponsive.
     * @dev Operator escape hatch for when a collector contract reverts on all calls
     * (broken upgrade, self-destruct, permanent pause), making normal reconciliation
     * impossible. Zeroes the agreement's maxNextClaim, removes it from pair tracking,
     * and triggers pair reconciliation to thaw/withdraw the freed escrow.
     *
     * Requires OPERATOR_ROLE. Only use when the collector cannot be fixed.
     *
     * @param collector The collector contract address
     * @param agreementId The agreement ID to force-remove
     */
    function forceRemoveAgreement(IAgreementCollector collector, bytes16 agreementId) external;

    /**
     * @notice Reconcile a (collector, provider) pair: rebalance escrow, withdraw
     * completed thaws, and remove tracking if fully drained.
     * @dev Permissionless. First updates escrow state (deposit deficit, thaw excess,
     * withdraw completed thaws), then removes pair tracking when both agreementCount
     * and escrow balance are zero. Also serves as the permissionless "poke" to rebalance
     * escrow after {IRecurringEscrowManagement-setEscrowBasis} or threshold/margin
     * changes. Returns true if the pair still has agreements or escrow is still thawing.
     * @param collector The collector address
     * @param provider The provider address
     * @return tracked True if the pair is still tracked after this call
     */
    function reconcileProvider(IAgreementCollector collector, address provider) external returns (bool tracked);

    /**
     * @notice Emergency: clear the eligibility oracle so all providers become eligible.
     * @dev Callable by PAUSE_ROLE holders. Use when the oracle is broken or compromised
     * and is wrongly blocking collections. The governor can later set a replacement oracle
     * via {IProviderEligibilityManagement.setProviderEligibilityOracle}.
     */
    function emergencyClearEligibilityOracle() external;
}
