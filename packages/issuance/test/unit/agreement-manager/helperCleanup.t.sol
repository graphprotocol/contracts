// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementHelperCleanupTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockRecurringCollector internal collector2;
    address internal indexer2;

    function setUp() public override {
        super.setUp();
        collector2 = new MockRecurringCollector();
        vm.label(address(collector2), "RecurringCollector2");
        indexer2 = makeAddr("indexer2");

        vm.prank(governor);
        agreementManager.grantRole(COLLECTOR_ROLE, address(collector2));
    }

    // -- Helpers --

    function _makeRCAFor(
        address provider,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca) {
        rca = _makeRCA(100 ether, 1 ether, 60, 3600, uint64(block.timestamp + 365 days));
        rca.serviceProvider = provider;
        rca.nonce = nonce;
    }

    function _offerForCollector(
        MockRecurringCollector collector,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        return agreementManager.offerAgreement(rca, IRecurringCollector(address(collector)));
    }

    function _setCanceledBySPOnCollector(
        MockRecurringCollector collector,
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal {
        collector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: uint64(block.timestamp),
                state: IRecurringCollector.AgreementState.CanceledByServiceProvider,
                authBasis: IRecurringCollector.AuthorizationBasis.Signature
            })
        );
    }

    // -- Tests: reconcile (provider) --

    function test_Reconcile_RemovesCanceledBySP() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    function test_Reconcile_SkipsStillClaimable() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementAccepted(id, rca, uint64(block.timestamp));

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    function test_Reconcile_MixedStates() public {
        // Agreement 1: canceled by SP (removable)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Agreement 2: still active (not removable)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        bytes16 id2 = _offerAgreement(rca2);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    function test_Reconcile_EmptyProvider() public {
        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 0);
    }

    function test_Reconcile_ExpiredOffer() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        _offerAgreement(rca);

        // Warp past deadline
        vm.warp(rca.deadline + 1);

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    function test_Reconcile_Permissionless() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 1);
    }

    // -- Tests: reconcilePair --

    function test_ReconcilePair_RemovesAgreementButPairStaysWhileThawing() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        (uint256 removed, bool pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);
        assertTrue(pairExists); // escrow still thawing — pair stays tracked

        // Drain escrow, then pair can be removed
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (, pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertFalse(pairExists);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 0);
    }

    function test_ReconcilePair_PairExistsWhenAgreementsRemain() public {
        // Two agreements, only one removable
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        bytes16 id2 = _offerAgreement(rca2);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        (uint256 removed, bool pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);
        assertTrue(pairExists);
    }

    function test_ReconcilePair_IsolatesCollectors() public {
        // Collector1 + indexer: canceled (removable)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Collector2 + indexer: active (not removable)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        rca2.dataService = dataService;
        _offerForCollector(collector2, rca2);

        // Reconcile only collector1's pair — escrow still thawing
        (uint256 removed, bool pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);
        assertTrue(pairExists); // escrow still thawing

        // Collector2's agreement untouched
        assertEq(agreementManager.getPairAgreementCount(address(collector2), indexer), 1);
    }

    // -- Tests: reconcileCollector --

    function test_ReconcileCollector_AllPairs() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer2, 2);
        bytes16 id2 = _offerAgreement(rca2);
        _setAgreementCanceledBySP(id2, rca2);

        (uint256 removed, bool collectorExists) = agreementHelper.reconcileCollector(address(recurringCollector));
        assertEq(removed, 2);
        assertTrue(collectorExists); // escrow still thawing for both pairs

        // Drain escrows, then collector can be removed
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        (, collectorExists) = agreementHelper.reconcileCollector(address(recurringCollector));
        assertFalse(collectorExists);
        assertEq(agreementManager.getCollectorCount(), 0);
    }

    function test_ReconcileCollector_PartialCleanup() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Active agreement — not removable
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer2, 2);
        bytes16 id2 = _offerAgreement(rca2);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        (uint256 removed, bool collectorExists) = agreementHelper.reconcileCollector(address(recurringCollector));
        assertEq(removed, 1);
        assertTrue(collectorExists); // indexer2 still has an active agreement
    }

    // -- Tests: reconcileAll --

    function test_ReconcileAll_FullSweep() public {
        // Collector1 + indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Collector2 + indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        bytes16 id2 = _offerForCollector(collector2, rca2);
        _setCanceledBySPOnCollector(collector2, id2, rca2);

        uint256 removed = agreementHelper.reconcileAll();
        assertEq(removed, 2);
        assertEq(agreementManager.getTotalAgreementCount(), 0);
        assertEq(agreementManager.getCollectorCount(), 2); // escrow still thawing

        // Drain escrows, then collectors can be removed
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(collector2), indexer);

        agreementHelper.reconcileAll();
        assertEq(agreementManager.getCollectorCount(), 0);
    }

    function test_ReconcileAll_EmptyState() public {
        uint256 removed = agreementHelper.reconcileAll();
        assertEq(removed, 0);
    }

    function test_ReconcileAll_PartialCleanup() public {
        // Removable
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Not removable
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer2, 2);
        bytes16 id2 = _offerAgreement(rca2);
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        uint256 removed = agreementHelper.reconcileAll();
        assertEq(removed, 1);
        assertEq(agreementManager.getTotalAgreementCount(), 1);
    }

    // -- Tests: reconcilePair (value reconciliation + cleanup) --

    function test_ReconcilePair_OnlyReconcilesPairAgreements() public {
        // Collector1 + indexer: cancel by SP
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        // Collector2 + indexer: still active (same provider, different collector)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        _offerForCollector(collector2, rca2);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Before reconcile, collector1's pair still has the old maxNextClaim
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);

        // Reconcile only collector1's pair
        (uint256 removed, ) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);

        // Collector1's pair reconciled to 0
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);

        // Collector2's pair untouched
        assertEq(agreementManager.getSumMaxNextClaim(IRecurringCollector(address(collector2)), indexer), maxClaim);
    }

    // -- Tests: reconcileAll (value reconciliation + cleanup) --

    function test_ReconcileAll_AllCollectorsAllProviders() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(indexer, 2);
        bytes16 id2 = _offerForCollector(collector2, rca2);
        _setCanceledBySPOnCollector(collector2, id2, rca2);

        uint256 removed = agreementHelper.reconcileAll();
        assertEq(removed, 2);

        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(IRecurringCollector(address(collector2)), indexer), 0);
    }

    // -- Tests: reconcile does reconcile+cleanup in single pass --

    function test_Reconcile_ReconcilesThenRemoves() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        // Set as CanceledBySP — after reconcile, maxNextClaim=0, then removable
        _setAgreementCanceledBySP(id, rca);

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    function test_Reconcile_NoopWhenAllActive() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementAccepted(id, rca, uint64(block.timestamp));

        uint256 removed = agreementHelper.reconcile(indexer);
        assertEq(removed, 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    // -- Tests: reconcilePair does reconcile+cleanup+pair removal --

    function test_ReconcilePair_RemovesAgreementAndPairAfterThaw() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(indexer, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        (uint256 removed, bool pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);
        assertTrue(pairExists); // escrow still thawing

        // Drain escrow, then pair can be removed
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (, pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertFalse(pairExists);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
