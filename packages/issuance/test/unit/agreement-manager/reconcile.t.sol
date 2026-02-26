// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { IIndexingAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIndexingAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IndexingAgreementManagerSharedTest } from "./shared.t.sol";

contract IndexingAgreementManagerReconcileTest is IndexingAgreementManagerSharedTest {
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
        uint256 initialMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
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
        agreementManager.reconcileAgreement(agreementId);

        uint256 newMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
        assertEq(newMaxClaim, 3600 ether);
        assertEq(agreementManager.getRequiredEscrow(indexer), 3600 ether);
    }

    function test_ReconcileAgreement_CanceledByServiceProvider() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 3700 ether);

        // SP cancels - immediately non-collectable
        _setAgreementCanceledBySP(agreementId, rca);

        agreementManager.reconcileAgreement(agreementId);

        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
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
        uint64 canceledAt = uint64(startTime + 2 hours);
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, canceledAt, 0);

        agreementManager.reconcileAgreement(agreementId);

        // Window = canceledAt - acceptedAt = 7200s, capped by maxSecondsPerCollection = 3600s
        // maxClaim = 1e18 * 3600 + 100e18 (never collected, so includes initial)
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), expectedMaxClaim);
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
        uint64 canceledAt = uint64(startTime + 2 hours);
        // lastCollectionAt == canceledAt means window is empty
        _setAgreementCanceledByPayer(agreementId, rca, acceptedAt, canceledAt, canceledAt);

        agreementManager.reconcileAgreement(agreementId);

        // collectionEnd = canceledAt, collectionStart = lastCollectionAt = canceledAt
        // window is empty -> maxClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
    }

    function test_ReconcileAgreement_SkipsNotAccepted() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);

        // Mock returns NotAccepted (default state in mock - zero struct)
        // reconcile should skip recalculation and preserve the original estimate

        agreementManager.reconcileAgreement(agreementId);

        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), originalMaxClaim);
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
        emit IIndexingAgreementManager.AgreementReconciled(agreementId, 3700 ether, 0);

        agreementManager.reconcileAgreement(agreementId);
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

        // maxClaim should remain 3700e18 (never collected, window > maxSecondsPerCollection)
        // No event should be emitted
        vm.recordLogs();
        agreementManager.reconcileAgreement(agreementId);

        // Check no AgreementReconciled event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 reconciledTopic = keccak256("AgreementReconciled(bytes16,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != reconciledTopic, "Unexpected AgreementReconciled event");
        }
    }

    function test_Reconcile_AllAgreementsForIndexer() public {
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

        // Cancel agreement 1 by SP
        _setAgreementCanceledBySP(id1, rca1);

        // Accept agreement 2 (collected once)
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(id2, rca2, uint64(block.timestamp), lastCollectionAt);
        vm.warp(lastCollectionAt);

        // Fund for reconcile
        token.mint(address(agreementManager), 1_000_000 ether);

        agreementManager.reconcile(indexer);

        // Agreement 1: CanceledBySP -> maxClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(id1), 0);
        // Agreement 2: collected, remaining window large, capped at maxSecondsPerCollection = 7200
        // maxClaim = 2e18 * 7200 = 14400e18 (no initial since collected)
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), 14400 ether);
        assertEq(agreementManager.getRequiredEscrow(indexer), 14400 ether);
    }

    function test_ReconcileAgreement_Revert_WhenNotOffered() public {
        bytes16 fakeId = bytes16(keccak256("fake"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IIndexingAgreementManager.IndexingAgreementManagerAgreementNotOffered.selector,
                fakeId
            )
        );
        agreementManager.reconcileAgreement(fakeId);
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

        agreementManager.reconcileAgreement(agreementId);

        // collectionEnd = endsAt, collectionStart = lastCollectionAt = endsAt
        // window empty -> maxClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
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

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim);

        // Simulate: agreement accepted and update applied on-chain (updateNonce = 1)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: rcau.endsAt,
                maxInitialTokens: rcau.maxInitialTokens,
                maxOngoingTokensPerSecond: rcau.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rcau.minSecondsPerCollection,
                maxSecondsPerCollection: rcau.maxSecondsPerCollection,
                updateNonce: 1,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        agreementManager.reconcileAgreement(agreementId);

        // Pending should be cleared, maxNextClaim recalculated from new terms
        // newMaxClaim = 2e18 * 7200 + 200e18 = 14600e18 (never collected, window > maxSecondsPerCollection)
        uint256 newMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), newMaxClaim);
        // Required = only new maxClaim (pending cleared)
        assertEq(agreementManager.getRequiredEscrow(indexer), newMaxClaim);
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

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;

        // Simulate: agreement accepted but update NOT yet applied (updateNonce = 0)
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        agreementManager.reconcileAgreement(agreementId);

        // maxNextClaim recalculated from original terms (same value since never collected)
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), originalMaxClaim);
        // Pending still present
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
