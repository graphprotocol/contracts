// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

/**
 * @title Interface for the {RecurringAgreementHelper} contract
 * @author Edge & Node
 * @notice Stateless convenience contract that provides batch reconciliation
 * functions for {RecurringAgreementManager}. Loops over agreements and delegates
 * each reconciliation to the manager's single-agreement `reconcileAgreement`.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IRecurringAgreementHelper {
    /**
     * @notice Reconcile all agreements for a provider (convenience function).
     * @dev Permissionless. Iterates all tracked agreements — O(n) gas,
     * may hit gas limits with many agreements. Prefer reconcileAgreement on the
     * manager for individual updates, or reconcileBatch for controlled batching.
     * @param provider The provider to reconcile
     */
    function reconcile(address provider) external;

    /**
     * @notice Reconcile a batch of agreements (caller-controlled batching).
     * @dev Permissionless. Allows callers to control gas usage by choosing which
     * agreements to reconcile in a single transaction. Skips non-existent agreements.
     * @param agreementIds The agreement IDs to reconcile
     */
    function reconcileBatch(bytes16[] calldata agreementIds) external;
}
