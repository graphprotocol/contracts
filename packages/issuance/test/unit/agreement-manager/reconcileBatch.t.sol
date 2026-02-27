// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerReconcileBatchTest is ServiceAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

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
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1 + maxClaim2);

        // Accept both and simulate CanceledBySP on agreement 1
        _setAgreementCanceledBySP(id1, rca1);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        // Reconcile both in batch
        bytes16[] memory ids = new bytes16[](2);
        ids[0] = id1;
        ids[1] = id2;
        agreementManager.reconcileBatch(ids);

        // Agreement 1 canceled by SP -> maxNextClaim = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(id1), 0);
        // Agreement 2 accepted, never collected -> maxNextClaim = initial + ongoing
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), maxClaim2);
        // Required should be just agreement 2 now
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim2);
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
        agreementManager.reconcileBatch(ids);

        // Real agreement should still be tracked
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getAgreementMaxNextClaim(realId), maxClaim);
    }

    function test_ReconcileBatch_Empty() public {
        // Empty array — should succeed silently
        bytes16[] memory ids = new bytes16[](0);
        agreementManager.reconcileBatch(ids);
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
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1);
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);

        // Cancel both by SP
        _setAgreementCanceledBySP(id1, rca1);
        _setAgreementCanceledBySP(id2, rca2);

        bytes16[] memory ids = new bytes16[](2);
        ids[0] = id1;
        ids[1] = id2;
        agreementManager.reconcileBatch(ids);

        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getRequiredEscrow(indexer2), 0);
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
        agreementManager.reconcileBatch(ids);
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
        assertEq(agreementManager.getRequiredEscrow(indexer), originalMaxClaim + pendingMaxClaim);

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
        agreementManager.reconcileBatch(ids);

        // Pending should be cleared; required escrow should be based on new terms
        uint256 newMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getRequiredEscrow(indexer), newMaxClaim);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
