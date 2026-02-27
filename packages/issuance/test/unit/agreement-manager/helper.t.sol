// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementHelper } from "../../../contracts/agreement/RecurringAgreementHelper.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementHelperTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Constructor tests --

    function test_Constructor_SetsManager() public view {
        assertEq(address(agreementHelper.MANAGER()), address(agreementManager));
    }

    function test_Constructor_Revert_ZeroAddress() public {
        vm.expectRevert(RecurringAgreementHelper.ManagerZeroAddress.selector);
        new RecurringAgreementHelper(address(0));
    }

    // -- reconcile(provider) tests --

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

        agreementHelper.reconcile(indexer);

        // Agreement 1: CanceledBySP -> maxClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(id1), 0);
        // Agreement 2: collected, remaining window large, capped at maxSecondsPerCollection = 7200
        // maxClaim = 2e18 * 7200 = 14400e18 (no initial since collected)
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), 14400 ether);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), 14400 ether);
    }

    function test_Reconcile_EmptyProvider() public {
        // reconcile for a provider with no agreements — should be a no-op
        address unknown = makeAddr("unknown");
        agreementHelper.reconcile(unknown);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), unknown), 0);
    }

    function test_Reconcile_IdempotentWhenUnchanged() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // First reconcile
        agreementHelper.reconcile(indexer);
        uint256 escrowAfterFirst = agreementManager.getRequiredEscrow(address(recurringCollector), indexer);
        uint256 maxClaimAfterFirst = agreementManager.getAgreementMaxNextClaim(agreementId);

        // Second reconcile should produce identical results (idempotent)
        vm.recordLogs();
        agreementHelper.reconcile(indexer);

        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), escrowAfterFirst);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), maxClaimAfterFirst);

        // No reconcile event on the second call since nothing changed
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 reconciledTopic = keccak256("AgreementReconciled(bytes16,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != reconciledTopic, "Unexpected AgreementReconciled event on idempotent call");
        }
    }

    function test_Reconcile_MultipleAgreements_MixedStates() public {
        // Three agreements for the same indexer, each in a different state
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

        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCA(
            0,
            3 ether,
            60,
            1800,
            uint64(block.timestamp + 365 days)
        );
        rca3.nonce = 3;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);
        bytes16 id3 = _offerAgreement(rca3);

        // id1: Canceled by SP -> maxClaim = 0
        _setAgreementCanceledBySP(id1, rca1);

        // id2: Accepted, collected -> no initial tokens
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(id2, rca2, uint64(block.timestamp), lastCollectionAt);

        // id3: Not yet accepted -> keep pre-offer estimate
        // (default mock returns NotAccepted)

        vm.warp(lastCollectionAt);
        token.mint(address(agreementManager), 1_000_000 ether);

        agreementHelper.reconcile(indexer);

        assertEq(agreementManager.getAgreementMaxNextClaim(id1), 0);
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), 14400 ether); // 2e18 * 7200
        // id3 unchanged: 3e18 * 1800 = 5400e18 (pre-offer estimate)
        assertEq(agreementManager.getAgreementMaxNextClaim(id3), 5400 ether);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), 14400 ether + 5400 ether);
    }

    // -- reconcileBatch tests --

    function test_ReconcileBatch_BasicBatch() public {
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

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), maxClaim1 + maxClaim2);

        // Accept both and simulate CanceledBySP on agreement 1
        _setAgreementCanceledBySP(id1, rca1);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        // Reconcile both in batch
        bytes16[] memory ids = new bytes16[](2);
        ids[0] = id1;
        ids[1] = id2;
        agreementHelper.reconcileBatch(ids);

        // Agreement 1 canceled by SP -> maxNextClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(id1), 0);
        // Agreement 2 accepted, never collected -> maxNextClaim = initial + ongoing
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), maxClaim2);
        // Required should be just agreement 2 now
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), maxClaim2);
    }

    function test_ReconcileBatch_SkipsNonExistent() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 realId = _offerAgreement(rca);
        bytes16 fakeId = bytes16(keccak256("nonexistent"));

        // Accept to enable reconciliation
        _setAgreementAccepted(realId, rca, uint64(block.timestamp));

        // Batch with a nonexistent id — should not revert
        bytes16[] memory ids = new bytes16[](2);
        ids[0] = fakeId;
        ids[1] = realId;
        agreementHelper.reconcileBatch(ids);

        // Real agreement should still be tracked
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getAgreementMaxNextClaim(realId), maxClaim);
    }

    function test_ReconcileBatch_Empty() public {
        // Empty array — should succeed silently
        bytes16[] memory ids = new bytes16[](0);
        agreementHelper.reconcileBatch(ids);
    }

    function test_ReconcileBatch_CrossIndexer() public {
        address indexer2 = makeAddr("indexer2");

        // Agreement 1 for default indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        // Agreement 2 for indexer2
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), maxClaim1);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer2), maxClaim2);

        // Cancel both by SP
        _setAgreementCanceledBySP(id1, rca1);
        _setAgreementCanceledBySP(id2, rca2);

        bytes16[] memory ids = new bytes16[](2);
        ids[0] = id1;
        ids[1] = id2;
        agreementHelper.reconcileBatch(ids);

        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer2), 0);
    }

    function test_ReconcileBatch_Permissionless() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // Anyone can call
        address anyone = makeAddr("anyone");
        bytes16[] memory ids = new bytes16[](1);
        ids[0] = agreementId;
        vm.prank(anyone);
        agreementHelper.reconcileBatch(ids);
    }

    function test_ReconcileBatch_ClearsPendingUpdate() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer a pending update (nonce 1)
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
        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(
            agreementManager.getRequiredEscrow(address(recurringCollector), indexer),
            originalMaxClaim + pendingMaxClaim
        );

        // Simulate: accepted with the update already applied (updateNonce >= pending)
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
                updateNonce: 1, // matches pending nonce, so update was applied
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        bytes16[] memory ids = new bytes16[](1);
        ids[0] = agreementId;
        agreementHelper.reconcileBatch(ids);

        // Pending should be cleared; required escrow should be based on new terms
        uint256 newMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), newMaxClaim);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
