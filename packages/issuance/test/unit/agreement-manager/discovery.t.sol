// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { Vm } from "forge-std/Vm.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

/// @notice Tests for agreement discovery via reconcileAgreement when the RAM
/// has never been notified about the agreement (no prior offer/callback).
/// This covers scenarios like:
/// - RAM deployed after agreements already existed on the collector
/// - Collector state changed out-of-band (e.g. SP cancel via collector directly)
/// - Callback was missed or failed silently
contract RecurringAgreementManagerDiscoveryTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Discovery via reconcileAgreement ====================

    function test_Discovery_AcceptedAgreement_ViaReconcile() public {
        // Set up an agreement directly on the mock collector — RAM never saw offer()
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // Fund the RAM so escrow management works
        token.mint(address(agreementManager), 1_000_000 ether);

        // RAM has no knowledge of this agreement
        assertEq(
            agreementManager.getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId).provider,
            address(0)
        );

        // reconcileAgreement should discover, register, and reconcile
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementAdded(
            agreementId,
            address(recurringCollector),
            dataService,
            indexer
        );

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertTrue(exists);
        assertEq(
            agreementManager.getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId).provider,
            indexer
        );

        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(
            agreementManager
                .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
                .maxNextClaim,
            expectedMaxClaim
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), expectedMaxClaim);
    }

    function test_Discovery_CanceledBySP_ViaReconcile() public {
        // Agreement was accepted and then SP-canceled before RAM ever learned about it
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _setAgreementCanceledBySP(agreementId, rca);

        token.mint(address(agreementManager), 1_000_000 ether);

        // SP cancel → SETTLED → maxNextClaim = 0 → should discover then immediately remove
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementAdded(
            agreementId,
            address(recurringCollector),
            dataService,
            indexer
        );
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        assertFalse(exists);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_Discovery_Idempotent_SecondReconcileNoReRegister() public {
        // Set up and discover an agreement
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        token.mint(address(agreementManager), 1_000_000 ether);

        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Second reconcile should NOT emit AgreementAdded again
        vm.recordLogs();
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Check no AgreementAdded was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 addedSig = IRecurringAgreementManagement.AgreementAdded.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != addedSig, "AgreementAdded should not be emitted on re-reconcile");
        }
    }

    // ==================== Rejection scenarios ====================

    function test_Discovery_RejectsUnknownAgreement() public {
        // Reconcile a completely unknown agreement ID
        bytes16 fakeId = bytes16(keccak256("nonexistent"));

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            fakeId,
            address(recurringCollector),
            IRecurringAgreementManagement.AgreementRejectionReason.UnknownAgreement
        );

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), fakeId);
        assertFalse(exists);
    }

    function test_Discovery_RejectsUnauthorizedCollector() public {
        // COLLECTOR_ROLE is required for discovery (first encounter).
        // Once tracked, reconciliation proceeds regardless of role.
        MockRecurringCollector rogue = new MockRecurringCollector();
        vm.label(address(rogue), "RogueCollector");

        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        // Store agreement on the rogue collector
        rogue.setAgreement(
            agreementId,
            _buildAgreementStorage(rca, REGISTERED | ACCEPTED, uint64(block.timestamp), 0, 0)
        );

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            agreementId,
            address(rogue),
            IRecurringAgreementManagement.AgreementRejectionReason.UnauthorizedCollector
        );

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(rogue)), agreementId);
        assertFalse(exists);
    }

    function test_Discovery_RejectsPayerMismatch() public {
        // Agreement where payer is NOT the RAM
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // Override payer to some other address
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            rca,
            REGISTERED | ACCEPTED,
            uint64(block.timestamp),
            0,
            0
        );
        data.payer = address(0xdead);
        recurringCollector.setAgreement(agreementId, data);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            agreementId,
            address(recurringCollector),
            IRecurringAgreementManagement.AgreementRejectionReason.PayerMismatch
        );

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);
    }

    function test_Discovery_RejectsUnauthorizedDataService() public {
        // Agreement with a dataService that does NOT have DATA_SERVICE_ROLE
        address rogueDataService = makeAddr("rogueDataService");

        bytes16 agreementId = bytes16(keccak256("rogue-ds-agreement"));

        IRecurringCollector.RecurringCollectionAgreement memory rogueRca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rogueRca.dataService = rogueDataService;
        recurringCollector.setAgreement(
            agreementId,
            _buildAgreementStorage(rogueRca, REGISTERED | ACCEPTED, uint64(block.timestamp), 0, 0)
        );

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRejected(
            agreementId,
            address(recurringCollector),
            IRecurringAgreementManagement.AgreementRejectionReason.UnauthorizedDataService
        );

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);
    }

    // ==================== Out-of-band state changes ====================

    function test_OutOfBand_AcceptedThenSPCancel_ReconcileRemoves() public {
        // Offer via normal path (RAM tracks it)
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint256 trackedMaxClaim = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;
        assertTrue(trackedMaxClaim > 0, "Should be tracked after offer");

        // SP cancels directly on collector (out-of-band, no callback to RAM)
        _setAgreementCanceledBySP(agreementId, rca);

        // RAM still thinks it has the old maxNextClaim
        assertEq(
            agreementManager
                .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
                .maxNextClaim,
            trackedMaxClaim,
            "RAM should still have stale maxNextClaim"
        );

        // Permissionless reconcile syncs the state
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_OutOfBand_CollectionReducesMaxClaim_ReconcileUpdates() public {
        // Offer and accept via normal path
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        uint256 preReconcileMax = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;

        // Simulate a collection happened out-of-band (lastCollectionAt advanced)
        uint64 collectionTime = uint64(block.timestamp + 1800);
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp), collectionTime);

        // Warp to collection time so the mock's maxNextClaim reflects the collection
        vm.warp(collectionTime);

        // Reconcile should update maxNextClaim (no more initialTokens, reduced window)
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);

        uint256 postReconcileMax = agreementManager
            .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
            .maxNextClaim;
        assertTrue(postReconcileMax < preReconcileMax, "maxNextClaim should decrease after collection");
        // After collection: no initialTokens, maxSeconds still 3600 → 1e18 * 3600 = 3600e18
        assertEq(postReconcileMax, 1 ether * 3600, "Should be ongoing-only after first collection");
    }

    // ==================== Permissionless reconcile ====================

    function test_Discovery_Permissionless() public {
        // Anyone can call reconcileAgreement — no role required
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        token.mint(address(agreementManager), 1_000_000 ether);

        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
