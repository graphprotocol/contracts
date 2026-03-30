// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import {
    IAgreementCollector,
    REGISTERED,
    ACCEPTED
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementManagerReconcileTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function test_ReconcileAgreement_AfterFirstCollection() public {
        // Offer: maxNextClaim = 1e18 * 3600 + 100e18 = 3700e18
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 initialMaxClaim = agreementManager.getAgreementMaxNextClaim(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(initialMaxClaim, 3700 ether);

        // Simulate: agreement accepted and first collection happened
        uint64 acceptedAt = uint64(block.timestamp);
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(agreementId, rca, acceptedAt, lastCollectionAt);

        // After first collection, maxInitialTokens no longer applies
        // New max = maxOngoingTokensPerSecond * min(remaining, maxSecondsPerCollection)
        // remaining = endsAt - lastCollectionAt (large), capped by maxSecondsPerCollection = 3600
        // New max = 1e18 * 3600 = 3600e18
        vm.warp(lastCollectionAt);
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        uint256 newMaxClaim = agreementManager.getAgreementMaxNextClaim(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(newMaxClaim, 3600 ether);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 3600 ether);
    }

    function test_ReconcileAgreement_CanceledByServiceProvider() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            3700 ether
        );

        // SP cancels - immediately non-collectable → reconcile deletes
        _setAgreementCanceledBySP(agreementId, rca);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertFalse(exists);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    function test_ReconcileAgreement_CanceledByPayer_WindowOpen() public {
        uint64 startTime = uint64(block.timestamp);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(startTime + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Payer cancels 2 hours from now, never collected
        uint64 acceptedAt = startTime;
        uint64 collectableUntil = uint64(startTime + 2 hours);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, collectableUntil, 0);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        // Window = collectableUntil - acceptedAt = 7200s, capped by maxSecondsPerCollection = 3600s
        // maxClaim = 1e18 * 3600 + 100e18 (never collected, so includes initial)
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            expectedMaxClaim
        );
    }

    function test_ReconcileAgreement_CanceledByPayer_WindowExpired() public {
        uint64 startTime = uint64(block.timestamp);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(startTime + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Payer cancels, and the collection already happened covering the full window
        uint64 acceptedAt = startTime;
        uint64 collectableUntil = uint64(startTime + 2 hours);
        // lastCollectionAt == collectableUntil means window is empty
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, collectableUntil, collectableUntil);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // collectionEnd = collectableUntil, collectionStart = lastCollectionAt = collectableUntil
        // window is empty -> maxClaim = 0 → deleted
        assertFalse(exists);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    function test_ReconcileAgreement_SkipsNotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = agreementManager.getAgreementMaxNextClaim(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );

        // Mock returns NotAccepted (default state in mock - zero struct)
        // reconcile should skip recalculation and preserve the original estimate

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            originalMaxClaim
        );
    }

    function test_ReconcileAgreement_EmitsEvent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels
        _setAgreementCanceledBySP(agreementId, rca);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementReconciled(agreementId, 3700 ether, 0);
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
    }

    function test_ReconcileAgreement_NoEmitWhenUnchanged() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted with same parameters - should produce same maxNextClaim
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // maxClaim should remain 3700e18 (never collected, maxSecondsPerCollection < window)
        // No event should be emitted
        vm.recordLogs();
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Check no AgreementReconciled or AgreementRemoved events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 reconciledTopic = keccak256("AgreementReconciled(bytes16,uint256,uint256)");
        bytes32 removedTopic = keccak256("AgreementRemoved(bytes16)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != reconciledTopic, "Unexpected AgreementReconciled event");
            assertTrue(logs[i].topics[0] != removedTopic, "Unexpected AgreementRemoved event");
        }
    }

    function test_ReconcileAgreement_ReturnsFalse_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));

        // Returns false (not exists) when agreement not found (idempotent)
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), fakeId);
        assertFalse(exists);
    }

    function test_ReconcileAgreement_ExpiredAgreement() public {
        uint64 endsAt = uint64(block.timestamp + 1 hours);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            endsAt
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted, collected at endsAt (fully expired)
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp), endsAt);
        vm.warp(endsAt);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // collectionEnd = endsAt, collectionStart = lastCollectionAt = endsAt
        // window empty -> maxClaim = 0 → deleted
        assertFalse(exists);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    function test_ReconcileAgreement_ClearsPendingUpdate() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Offer a pending update
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
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);

        // Simulate: agreement accepted and update applied on-chain (updateNonce = 1)
        IRecurringCollector.RecurringCollectionAgreement memory updatedRca = _makeRCA(
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection,
            rcau.endsAt
        );
        updatedRca.payer = rca.payer;
        updatedRca.dataService = rca.dataService;
        updatedRca.serviceProvider = rca.serviceProvider;
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            updatedRca,
            REGISTERED | ACCEPTED,
            uint64(block.timestamp),
            0,
            0
        );
        data.updateNonce = 1;
        recurringCollector.setAgreement(agreementId, data);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        // Pending should be cleared, maxNextClaim recalculated from new terms
        // newMaxClaim = 2e18 * 7200 + 200e18 = 14600e18 (never collected, maxSecondsPerCollection < window)
        uint256 newMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            newMaxClaim
        );
        // Required = only new maxClaim (pending cleared)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), newMaxClaim);
    }

    function test_ReconcileAgreement_KeepsPendingUpdate_WhenNotYetApplied() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Offer a pending update
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

        // Full update max = 14600
        uint256 pendingMaxClaim = 14600 ether;

        // Simulate: agreement accepted but update NOT yet applied (updateNonce = 0)
        // Must preserve pending terms on the collector (setAgreementAccepted would erase them)
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            rca,
            REGISTERED | ACCEPTED,
            uint64(block.timestamp),
            0,
            0
        );
        data.pendingTerms = IRecurringCollector.AgreementTerms({
            deadline: 0,
            endsAt: rcau.endsAt,
            maxInitialTokens: rcau.maxInitialTokens,
            maxOngoingTokensPerSecond: rcau.maxOngoingTokensPerSecond,
            minSecondsPerCollection: rcau.minSecondsPerCollection,
            maxSecondsPerCollection: rcau.maxSecondsPerCollection,
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
            hash: bytes32(0),
            metadata: ""
        });
        recurringCollector.setAgreement(agreementId, data);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        // maxNextClaim stores max(active, pending)
        // max(3700, 14600) = 14600 (pending dominates, update not yet applied)
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            pendingMaxClaim
        );
        // Sum also reflects the max
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);
    }

    // -- Tests merged from remove (cleanup behavior) --

    function test_ReconcileAgreement_ReturnsTrue_WhenStillClaimable_Accepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted but never collected - still claimable
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
    }

    function test_ReconcileAgreement_DeletesExpiredOffer() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Warp past the RCA deadline (default: block.timestamp + 1 hours in _makeRCA)
        vm.warp(block.timestamp + 2 hours);

        // Agreement not accepted + past deadline — should be deleted
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertFalse(exists);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_ReconcileAgreement_ReturnsTrue_WhenStillClaimable_NotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Not accepted yet, before deadline - still potentially claimable
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
    }

    function test_ReconcileAgreement_ReturnsTrue_WhenCanceledByPayer_WindowStillOpen() public {
        uint64 startTime = uint64(block.timestamp);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(startTime + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Payer canceled but window is still open (not yet collected)
        uint64 collectableUntil = uint64(startTime + 2 hours);
        _setAgreementCanceledByPayer(agreementId, rca, startTime, collectableUntil, 0);

        // Still claimable: window = collectableUntil - acceptedAt = 7200s, capped at 3600s
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
    }

    function test_ReconcileAgreement_ReducesRequiredEscrow_WithMultipleAgreements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether; // 3700e18
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether; // 14600e18
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1 + maxClaim2);

        // Cancel agreement 1 by SP and reconcile it (deletes)
        _setAgreementCanceledBySP(id1, rca1);
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);
        assertFalse(exists);

        // Only agreement 2's original maxClaim remains
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim2);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        // Agreement 2 still tracked
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), id2),
            maxClaim2
        );
    }

    function test_ReconcileAgreement_Permissionless() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels
        _setAgreementCanceledBySP(agreementId, rca);

        // Anyone can reconcile
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);

        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    function test_ReconcileAgreement_ClearsPendingUpdate_WhenCanceled() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer a pending update
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

        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pendingMaxClaim = 14600 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);

        // SP cancels - immediately removable
        _setAgreementCanceledBySP(agreementId, rca);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);

        // Both original and pending should be cleared from sumMaxNextClaim
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
