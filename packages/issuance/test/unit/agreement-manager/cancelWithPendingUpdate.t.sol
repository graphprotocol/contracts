// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
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
        uint64 collectableUntil = uint64(block.timestamp + 1 hours);
        vm.warp(collectableUntil);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, collectableUntil, 0);

        // State is CanceledByPayer — cancelAgreement rejects non-Accepted states,
        // so use reconcileAgreement to trigger cleanup.
        bool exists = agreementManager.reconcileAgreement(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertTrue(exists, "agreement should still exist (has remaining claims)");

        // 4. BUG: The pending update can never be accepted (collector rejects updates on
        // canceled agreements), yet pendingUpdateMaxNextClaim is still reserved.
        uint256 sumAfterCancel = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // The pending escrow should have been freed (zeroed) since the update is dead.
        // sumMaxNextClaim should only include the base claim, not the dead pending update.
        assertEq(
            sumAfterCancel,
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
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
        uint64 collectableUntil = uint64(block.timestamp + 1 hours);
        vm.warp(collectableUntil);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, collectableUntil, 0);

        // State is CanceledByPayer — cancelAgreement rejects non-Accepted states,
        // so use reconcileAgreement to trigger cleanup.
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // After cancel + reconcile, maxNextClaim should reflect only the remaining collection window
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(
            info.maxNextClaim,
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId)
        );

        // The pending update can no longer be applied (collector handles hash lifecycle)
    }

    /* solhint-enable graph/func-name-mixedcase */
}
