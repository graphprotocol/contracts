// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementManagerCascadeCleanupTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockRecurringCollector internal collector2;

    function setUp() public override {
        super.setUp();
        collector2 = new MockRecurringCollector();
        vm.label(address(collector2), "RecurringCollector2");

        vm.prank(governor);
        agreementManager.grantRole(COLLECTOR_ROLE, address(collector2));
    }

    // -- Helpers --

    function _collector2() internal view returns (IRecurringCollector) {
        return IRecurringCollector(address(collector2));
    }

    function _makeRCAForCollector(
        MockRecurringCollector collector,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(agreementManager),
            dataService: dataService,
            serviceProvider: indexer,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: 3600,
            nonce: nonce,
            metadata: ""
        });
        agreementId = collector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
    }

    function _makeRCAForProvider(
        address provider,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(agreementManager),
            dataService: dataService,
            serviceProvider: provider,
            maxInitialTokens: 100 ether,
            maxOngoingTokensPerSecond: 1 ether,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: 3600,
            nonce: nonce,
            metadata: ""
        });
        agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
    }

    function _offerForCollector(
        MockRecurringCollector collector,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        return agreementManager.offerAgreement(rca, IRecurringCollector(address(collector)));
    }

    // -- Tests: Enumeration after offer --

    function test_Cascade_SingleAgreement_PopulatesSets() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        _offerAgreement(rca);

        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorAt(0), address(recurringCollector));
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getCollectorProviderAt(address(recurringCollector), 0), indexer);
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 1);
    }

    function test_Cascade_TwoAgreements_SamePair_CountIncrements() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(recurringCollector, 1);
        _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(recurringCollector, 2);
        _offerAgreement(rca2);

        // Sets still have one entry each, but pair count is 2
        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 2);
    }

    function test_Cascade_MultiCollector_BothTracked() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(recurringCollector, 1);
        _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(collector2, 2);
        _offerForCollector(collector2, rca2);

        assertEq(agreementManager.getCollectorCount(), 2);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getCollectorProviderCount(address(collector2)), 1);
    }

    function test_Cascade_MultiProvider_BothTracked() public {
        address indexer2 = makeAddr("indexer2");

        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForProvider(indexer, 1);
        _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForProvider(indexer2, 2);
        _offerAgreement(rca2);

        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 2);
    }

    // -- Tests: Cascade on reconciliation --

    function test_Cascade_ReconcileOneOfTwo_PairStaysTracked() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id1 = _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(recurringCollector, 2);
        _offerAgreement(rca2);

        // Reconcile first (SP canceled → deleted)
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);

        // Pair still tracked
        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 1);
    }

    function test_Cascade_ReconcileLast_PairStaysWhileEscrowThawing() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);

        _setAgreementCanceledBySP(id, rca);
        agreementManager.reconcileAgreement(id);

        // Agreement removed, but pair stays tracked while escrow is thawing
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 0);
        assertEq(agreementManager.getCollectorCount(), 1, "collector stays tracked during thaw");
        assertEq(
            agreementManager.getCollectorProviderCount(address(recurringCollector)),
            1,
            "provider stays tracked during thaw"
        );

        // After thaw period, reconcileCollectorProvider reconciles escrow and removes
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.CollectorProviderRemoved(address(recurringCollector), indexer);
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.CollectorRemoved(address(recurringCollector));

        assertFalse(agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer));

        assertEq(agreementManager.getCollectorCount(), 0);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 0);
    }

    function test_Cascade_ReconcileLastProvider_CollectorCleanedUp_OtherCollectorRemains() public {
        // Set up: collector1 with indexer, collector2 with indexer
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id1 = _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(collector2, 2);
        _offerForCollector(collector2, rca2);

        // Reconcile collector1's agreement — pair stays tracked during thaw
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);

        assertEq(agreementManager.getCollectorCount(), 2, "both collectors tracked during thaw");
        assertEq(
            agreementManager.getCollectorProviderCount(address(recurringCollector)),
            1,
            "provider stays during thaw"
        );

        // After thaw period, reconcileCollectorProvider reconciles escrow and removes
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);

        // collector1 cleaned up, collector2 remains
        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorAt(0), address(collector2));
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 0);
        assertEq(agreementManager.getCollectorProviderCount(address(collector2)), 1);
    }

    function test_Cascade_ReconcileProvider_CollectorRetainsOtherProvider() public {
        address indexer2 = makeAddr("indexer2");

        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForProvider(indexer, 1);
        bytes16 id1 = _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForProvider(indexer2, 2);
        _offerAgreement(rca2);

        // Reconcile indexer's agreement — pair stays tracked during thaw
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);

        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(
            agreementManager.getCollectorProviderCount(address(recurringCollector)),
            2,
            "both providers tracked during thaw"
        );
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 0);
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer2), 1);

        // After thaw period, reconcileCollectorProvider reconciles escrow and removes
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);

        // Now only indexer2 remains
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getCollectorProviderAt(address(recurringCollector), 0), indexer2);
    }

    // -- Tests: Re-addition after cleanup --

    function test_Cascade_ReaddAfterFullCleanup() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);

        // Reconcile agreement — pair stays tracked during escrow thaw
        _setAgreementCanceledBySP(id, rca);
        agreementManager.reconcileAgreement(id);
        assertEq(agreementManager.getCollectorCount(), 1, "stays tracked during thaw");

        // After thaw period, full cleanup via reconcileCollectorProvider
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertEq(agreementManager.getCollectorCount(), 0);

        // Re-add — sets repopulate
        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(recurringCollector, 2);
        _offerAgreement(rca2);

        assertEq(agreementManager.getCollectorCount(), 1);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 1);
    }

    // -- Tests: Revoke also cascades --

    function test_Cascade_RevokeOffer_DeferredCleanup() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);

        assertEq(agreementManager.getCollectorCount(), 1);

        vm.prank(operator);
        agreementManager.revokeOffer(id);

        // Agreement gone, but pair stays tracked during escrow thaw
        assertEq(agreementManager.getPairAgreementCount(address(recurringCollector), indexer), 0);
        assertEq(agreementManager.getCollectorCount(), 1, "stays tracked during thaw");

        // After thaw period, reconcileCollectorProvider reconciles escrow and removes
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);

        assertEq(agreementManager.getCollectorCount(), 0);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 0);
    }

    // -- Tests: Permissionless safety valve functions --

    function test_ReconcileCollectorProvider_ReturnsTrue_WhenAgreementsExist() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        _offerAgreement(rca);

        // Exists: pair has agreements
        bool exists = agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertTrue(exists);
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 1);
    }

    function test_ReconcileCollectorProvider_ReturnsFalse_WhenNotTracked() public {
        // Not exists: pair was never added
        bool exists = agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertFalse(exists);
    }

    function test_ReconcileCollectorProvider_ReturnsTrue_WhenEscrowThawing() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);

        _setAgreementCanceledBySP(id, rca);
        agreementManager.reconcileAgreement(id);

        // Exists: escrow still has pending thaw
        bool exists = agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertTrue(exists);
    }

    function test_ReconcileCollectorProvider_ReturnsFalse_AfterThawPeriod() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);

        _setAgreementCanceledBySP(id, rca);
        agreementManager.reconcileAgreement(id);

        // After thaw period, reconcileCollectorProvider reconciles escrow internally
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        bool exists = agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertFalse(exists);
    }

    function test_ReconcileCollectorProvider_Permissionless() public {
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        bool exists = agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
        assertFalse(exists);
    }

    // -- Tests: Helper two-phase cleanup --

    function test_Helper_ReconcilePair_FirstCallStartsThaw_SecondCallCompletes() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        // First call: reconciles agreement (deletes it), starts thaw, but pair stays
        (uint256 removed, bool pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 1);
        assertTrue(pairExists, "pair stays during thaw");

        // Second call after thaw period: completes withdrawal and removes pair
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        (removed, pairExists) = agreementHelper.reconcilePair(address(recurringCollector), indexer);
        assertEq(removed, 0, "no agreements left to reconcile");
        assertFalse(pairExists, "pair gone after escrow recovered");
    }

    function test_Helper_ReconcileCollector_TwoPhase() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAForCollector(recurringCollector, 1);
        bytes16 id = _offerAgreement(rca);
        _setAgreementCanceledBySP(id, rca);

        // First call: reconciles agreement (deletes it), starts thaw
        (uint256 removed, bool collectorExists) = agreementHelper.reconcileCollector(address(recurringCollector));
        assertEq(removed, 1);
        assertTrue(collectorExists, "collector stays during thaw");

        // Second call after thaw: completes
        vm.warp(block.timestamp + paymentsEscrow.THAWING_PERIOD() + 1);
        (removed, collectorExists) = agreementHelper.reconcileCollector(address(recurringCollector));
        assertEq(removed, 0);
        assertFalse(collectorExists, "collector gone after escrow recovered");
    }

    // -- Tests: Pagination --

    function test_GetCollectors_Enumeration() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForCollector(recurringCollector, 1);
        _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForCollector(collector2, 2);
        _offerForCollector(collector2, rca2);

        // Full enumeration
        assertEq(agreementManager.getCollectorCount(), 2);
        address collector0 = agreementManager.getCollectorAt(0);
        address collector1 = agreementManager.getCollectorAt(1);

        // Individual access by index
        assertEq(agreementManager.getCollectorAt(0), collector0);
        assertEq(agreementManager.getCollectorAt(1), collector1);
    }

    function test_GetCollectorProviders_Enumeration() public {
        address indexer2 = makeAddr("indexer2");

        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAForProvider(indexer, 1);
        _offerAgreement(rca1);

        (IRecurringCollector.RecurringCollectionAgreement memory rca2, ) = _makeRCAForProvider(indexer2, 2);
        _offerAgreement(rca2);

        // Full enumeration
        assertEq(agreementManager.getCollectorProviderCount(address(recurringCollector)), 2);
        address provider0 = agreementManager.getCollectorProviderAt(address(recurringCollector), 0);
        address provider1 = agreementManager.getCollectorProviderAt(address(recurringCollector), 1);

        // Individual access by index
        assertEq(agreementManager.getCollectorProviderAt(address(recurringCollector), 0), provider0);
        assertEq(agreementManager.getCollectorProviderAt(address(recurringCollector), 1), provider1);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
