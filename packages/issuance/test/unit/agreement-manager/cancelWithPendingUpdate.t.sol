// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

/// @notice Tests that canceling an agreement correctly clears pending update escrow.
contract RecurringAgreementManagerCancelWithPendingUpdateTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Demonstrates the bug: when an accepted agreement with a pending (unapplied)
    /// update is canceled, the pendingUpdateMaxNextClaim escrow is NOT freed during
    /// cancelAgreement. The escrow remains locked until the agreement is fully drained
    /// and deleted, even though the update can never be accepted (collector rejects
    /// updates on non-Accepted agreements).
    function test_CancelAgreement_PendingUpdateEscrowNotFreed() public {
        // 1. Offer and accept an agreement
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        uint64 acceptedAt = uint64(block.timestamp);
        _setAgreementAccepted(agreementId, rca, acceptedAt);

        // 2. Offer an update (nonce=1) — reserves additional escrow
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pendingMaxClaim = 14600 ether;
        assertEq(
            agreementManager.getSumMaxNextClaim(_collector(), indexer),
            pendingMaxClaim,
            "escrow reserved for max of current and pending"
        );

        // 3. Cancel the agreement — simulate CanceledByPayer with remaining collection window.
        // The collector still has a non-zero maxNextClaim (remaining window to collect).
        // updateNonce is still 0 — the pending update was never applied.
        uint64 canceledAt = uint64(block.timestamp + 1 hours);
        vm.warp(canceledAt);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, canceledAt, 0);

        // State is CanceledByPayer — cancelAgreement rejects non-Accepted states,
        // so use reconcileAgreement to trigger cleanup.
        bool exists = agreementManager.reconcileAgreement(agreementId);
        assertTrue(exists, "agreement should still exist (has remaining claims)");

        // 4. BUG: The pending update can never be accepted (collector rejects updates on
        // canceled agreements), yet pendingUpdateMaxNextClaim is still reserved.
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        uint256 sumAfterCancel = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // The pending escrow should have been freed (zeroed) since the update is dead.
        // This assertion demonstrates the bug — it will FAIL because the pending escrow
        // is still included in sumMaxNextClaim.
        assertEq(
            info.pendingUpdateMaxNextClaim,
            0,
            "BUG: pending update escrow should be zero after cancel (update can never be applied)"
        );
        assertEq(
            sumAfterCancel,
            agreementManager.getAgreementMaxNextClaim(agreementId),
            "BUG: sumMaxNextClaim should only include the base claim, not the dead pending update"
        );
    }

    /// @notice After cancel + reconcile, pending update escrow and hash are fully cleared.
    function test_CancelAgreement_PendingClearedAfterReconcile() public {
        // 1. Offer and accept
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint64 acceptedAt = uint64(block.timestamp);
        _setAgreementAccepted(agreementId, rca, acceptedAt);

        // 2. Offer update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        // 3. Cancel (CanceledByPayer, remaining window)
        uint64 canceledAt = uint64(block.timestamp + 1 hours);
        vm.warp(canceledAt);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, canceledAt, 0);

        // State is CanceledByPayer — cancelAgreement rejects non-Accepted states,
        // so use reconcileAgreement to trigger cleanup.
        agreementManager.reconcileAgreement(agreementId);

        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.pendingUpdateMaxNextClaim, 0, "pending escrow should be zero after cancel");
        assertEq(info.pendingUpdateNonce, 0, "pending nonce should be zero after cancel");
        assertEq(info.pendingUpdateHash, bytes32(0), "pending hash should be zero after cancel");

        // 5. The dead update hash should no longer be authorized
        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        bytes4 result = agreementManager.approveAgreement(updateHash);
        assertTrue(result != agreementManager.approveAgreement.selector, "dead hash should not be authorized");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
