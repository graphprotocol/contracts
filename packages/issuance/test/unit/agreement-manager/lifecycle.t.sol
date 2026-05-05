// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementLifecycleTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    uint256 internal constant THAW_PERIOD = 1 days;

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
        MockRecurringCollector,
        address provider,
        uint256 maxInitial,
        uint256 maxOngoing,
        uint32 maxSec,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca) {
        rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(agreementManager),
            dataService: dataService,
            serviceProvider: provider,
            maxInitialTokens: maxInitial,
            maxOngoingTokensPerSecond: maxOngoing,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: maxSec,
            conditions: 0,
            nonce: nonce,
            metadata: ""
        });
    }

    function _offerForCollector(
        MockRecurringCollector collector,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        return
            agreementManager.offerAgreement(IRecurringCollector(address(collector)), OFFER_TYPE_NEW, abi.encode(rca));
    }

    function _setCanceledBySPOnCollector(
        MockRecurringCollector collector,
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal {
        collector.setAgreement(
            agreementId,
            _buildAgreementStorage(
                rca,
                REGISTERED | ACCEPTED | NOTICE_GIVEN | SETTLED | BY_PROVIDER,
                uint64(block.timestamp),
                uint64(block.timestamp),
                0
            )
        );
    }

    // -- Tests: Single Agreement Full Lifecycle --

    function test_Lifecycle_OfferAcceptCancelReconcileCleanup() public {
        // 1. Start empty
        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        // 2. Offer
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // 3. Audit: agreement tracked, escrow deposited
        g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, maxClaim);
        assertEq(g.collectorCount, 1);

        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertEq(p.agreementCount, 1);
        assertEq(p.sumMaxNextClaim, maxClaim);
        assertEq(p.escrow.balance, maxClaim); // Full mode

        // 4. Accept
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // 5. Simulate first collection
        vm.warp(block.timestamp + 1800);
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp - 1800), uint64(block.timestamp));

        // 6. Reconcile — maxInitialTokens drops out after first collection
        agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);
        uint256 reducedMaxClaim = 1 ether * 3600; // no more initial
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), reducedMaxClaim);

        // 7. Cancel by SP
        _setAgreementCanceledBySP(agreementId, rca);

        // 8. Reconcile
        (uint256 removed, ) = agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(removed, 1);

        // 9. Agreements gone, but escrow still thawing — collector stays tracked
        g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, 0);
        assertEq(g.collectorCount, 1); // still tracked — escrow not yet drained

        // 10. Escrow is thawing
        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertTrue(0 < p.escrow.tokensThawing);

        // 11. Wait for thaw and withdraw
        vm.warp(block.timestamp + THAW_PERIOD + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.balance, 0);
        assertEq(p.escrow.tokensThawing, 0);

        // 12. Now that escrow is drained, reconcile removes tracking
        agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);

        g = agreementHelper.auditGlobal();
        assertEq(g.collectorCount, 0); // fully cleaned up
    }

    // -- Tests: Escrow Basis Changes --

    function test_Lifecycle_EscrowBasisChange_FullToOnDemand() public {
        // Offer in Full mode — escrow deposited
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertEq(p.escrow.balance, maxClaim);
        assertEq(p.escrow.tokensThawing, 0);

        // Switch to OnDemand
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(uint256(g.escrowBasis), uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand));

        // reconcileProvider — OnDemand has min=0, max=sumMaxNextClaim.
        // Balance == max so no thaw needed (balanced)
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        // In OnDemand with balance == max, no thaw
        assertEq(p.escrow.balance, maxClaim);

        // Switch to JustInTime — should start thawing everything
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.tokensThawing, maxClaim); // thawing everything

        // Wait for thaw and withdraw
        vm.warp(block.timestamp + THAW_PERIOD + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.balance, 0);

        // Switch back to Full — should deposit again
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.balance, maxClaim);
        assertEq(p.escrow.tokensThawing, 0);
    }

    // -- Tests: Multi-Collector Multi-Provider --

    function test_Lifecycle_MultiCollectorMultiProvider() public {
        // Offer: collector1+indexer, collector1+indexer2, collector2+indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 id1 = _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(
            recurringCollector,
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );
        bytes16 id2 = _offerAgreement(rca2);
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCAFor(
            collector2,
            indexer,
            50 ether,
            0.5 ether,
            1800,
            3
        );
        bytes16 id3 = _offerForCollector(collector2, rca3);
        uint256 maxClaim3 = 0.5 ether * 1800 + 50 ether;

        // Audit global
        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, maxClaim1 + maxClaim2 + maxClaim3);
        assertEq(g.collectorCount, 2);

        // Audit pairs per collector
        IRecurringAgreementHelper.ProviderAudit[] memory c1Pairs = agreementHelper.auditProviders(
            IAgreementCollector(address(recurringCollector))
        );
        assertEq(c1Pairs.length, 2);

        IRecurringAgreementHelper.ProviderAudit[] memory c2Pairs = agreementHelper.auditProviders(
            IAgreementCollector(address(collector2))
        );
        assertEq(c2Pairs.length, 1);
        assertEq(c2Pairs[0].sumMaxNextClaim, maxClaim3);

        // Accept all, cancel collector1+indexer by SP
        _setAgreementAccepted(id1, rca1, uint64(block.timestamp));
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));
        _setAgreementCanceledBySP(id1, rca1);

        // Selective reconcile: only collector1+indexer — escrow still thawing
        (uint256 removed, bool providerExists) = agreementHelper.reconcile(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertEq(removed, 1);
        assertTrue(providerExists); // escrow still thawing

        // collector1 still has indexer2 (+ c1+indexer pair tracked due to thawing escrow)
        assertEq(agreementManager.getProviderCount(IAgreementCollector(address(recurringCollector))), 2);

        // Global state updated
        g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, maxClaim2 + maxClaim3);

        // Cancel remaining and full reconcile
        _setAgreementCanceledBySP(id2, rca2);
        _setCanceledBySPOnCollector(collector2, id3, rca3);

        // Reconcile all (reconcile + cleanup in single pass)
        uint256 totalRemoved = agreementHelper.reconcileAll();
        assertEq(totalRemoved, 2);

        // Agreements gone, but escrows still thawing — collectors stay tracked
        g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, 0);
        assertEq(g.collectorCount, 2); // still tracked — escrow not yet drained

        // Escrows should be thawing for all pairs
        IRecurringAgreementHelper.ProviderAudit memory p1 = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertTrue(0 < p1.escrow.tokensThawing, "c1+indexer should be thawing");

        IRecurringAgreementHelper.ProviderAudit memory p2 = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer2
        );
        assertTrue(0 < p2.escrow.tokensThawing, "c1+indexer2 should be thawing");

        IRecurringAgreementHelper.ProviderAudit memory p3 = agreementHelper.auditProvider(
            IAgreementCollector(address(collector2)),
            indexer
        );
        assertTrue(0 < p3.escrow.tokensThawing, "c2+indexer should be thawing");

        // Wait for thaw, withdraw all
        vm.warp(block.timestamp + THAW_PERIOD + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer2);
        agreementManager.reconcileProvider(IAgreementCollector(address(collector2)), indexer);

        // All escrows drained
        p1 = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p1.escrow.balance, 0);
        assertEq(p1.escrow.tokensThawing, 0);

        p2 = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer2);
        assertEq(p2.escrow.balance, 0);
        assertEq(p2.escrow.tokensThawing, 0);

        p3 = agreementHelper.auditProvider(IAgreementCollector(address(collector2)), indexer);
        assertEq(p3.escrow.balance, 0);
        assertEq(p3.escrow.tokensThawing, 0);

        // Now reconcile tracking (escrow drained, so reconcileProvider succeeds)
        agreementHelper.reconcileAll();

        g = agreementHelper.auditGlobal();
        assertEq(g.collectorCount, 0); // fully cleaned up
    }

    // -- Tests: Expired Offer Cleanup --

    function test_Lifecycle_ExpiredOffer_CleanupRemoves() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);

        // Before deadline: not removable
        (uint256 removed, ) = agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(removed, 0);

        // Warp past deadline
        vm.warp(rca.deadline + 1);

        // Now removable
        (removed, ) = agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(removed, 1);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);

        // Escrow deposited in Full mode should now be thawing
        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertTrue(0 < p.escrow.tokensThawing, "escrow should be thawing after expired offer removal");

        // Wait for thaw and withdraw
        vm.warp(block.timestamp + THAW_PERIOD + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.balance, 0);
        assertEq(p.escrow.tokensThawing, 0);
    }

    // -- Tests: reconcile Isolation --

    function test_Lifecycle_ReconcilePair_IsolatesCollectors() public {
        // Both collectors have agreements with the same indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 id1 = _offerAgreement(rca1);
        _setAgreementCanceledBySP(id1, rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAFor(
            collector2,
            indexer,
            200 ether,
            2 ether,
            7200,
            2
        );
        _offerForCollector(collector2, rca2);

        // Reconcile only collector1's pair — escrow still thawing so pair still exists
        (uint256 removed, bool providerExists) = agreementHelper.reconcile(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertEq(removed, 1);
        assertTrue(providerExists); // escrow still thawing, pair stays tracked

        // Collector2's agreement untouched
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(IRecurringCollector(address(collector2)), indexer), maxClaim2);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(collector2)), indexer), 1);

        // Collector1's escrow should be thawing after reconcile
        IRecurringAgreementHelper.ProviderAudit memory p1 = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertTrue(0 < p1.escrow.tokensThawing, "c1 escrow should be thawing after reconcile");

        // Collector2's escrow should still be fully deposited (not thawing)
        IRecurringAgreementHelper.ProviderAudit memory p2 = agreementHelper.auditProvider(
            IAgreementCollector(address(collector2)),
            indexer
        );
        assertEq(p2.escrow.balance, maxClaim2);
        assertEq(p2.escrow.tokensThawing, 0);

        // Wait for thaw, then drain collector1's escrow
        vm.warp(block.timestamp + THAW_PERIOD + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p1 = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p1.escrow.balance, 0);
        assertEq(p1.escrow.tokensThawing, 0);

        // Now pair can be fully removed
        (, providerExists) = agreementHelper.reconcile(IAgreementCollector(address(recurringCollector)), indexer);
        assertFalse(providerExists); // escrow drained, pair removed
    }

    // -- Tests: Escrow Basis Mid-Lifecycle with Audit Verification --

    function test_Lifecycle_EscrowBasisChange_OnDemandToFull() public {
        // Start in OnDemand mode
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        // Offer — OnDemand: min=0, max=sumMaxNextClaim. No deposit (min=0).
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAFor(
            recurringCollector,
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer
        );
        assertEq(p.sumMaxNextClaim, maxClaim);
        // OnDemand: no deposit, but _updateEscrow in offerAgreement may have deposited
        // Actually in OnDemand min=0 so no deposit happens
        assertEq(p.escrow.balance, 0);

        // Switch to Full
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(p.escrow.balance, maxClaim); // Full deposits everything
    }

    /* solhint-enable graph/func-name-mixedcase */
}
