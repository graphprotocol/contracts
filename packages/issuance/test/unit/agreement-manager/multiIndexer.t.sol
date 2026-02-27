// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerMultiIndexerTest is ServiceAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    address internal indexer2;
    address internal indexer3;

    function setUp() public virtual override {
        super.setUp();
        indexer2 = makeAddr("indexer2");
        indexer3 = makeAddr("indexer3");
    }

    // -- Helpers --

    function _makeRCAForIndexer(
        address sp,
        uint256 maxInitial,
        uint256 maxOngoing,
        uint32 maxSec,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );
        rca.serviceProvider = sp;
        rca.nonce = nonce;
        return rca;
    }

    // -- Isolation: offer/requiredEscrow --

    function test_MultiIndexer_OfferIsolation() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCAForIndexer(
            indexer3,
            50 ether,
            0.5 ether,
            1800,
            3
        );

        _offerAgreement(rca1);
        _offerAgreement(rca2);
        _offerAgreement(rca3);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        uint256 maxClaim3 = 0.5 ether * 1800 + 50 ether;

        // Each indexer has independent requiredEscrow
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1);
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);
        assertEq(agreementManager.getRequiredEscrow(indexer3), maxClaim3);

        // Each has exactly 1 agreement
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer2), 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer3), 1);

        // Each has independent escrow balance
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim1
        );
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer2).balance,
            maxClaim2
        );
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer3).balance,
            maxClaim3
        );
    }

    // -- Isolation: revoke one indexer doesn't affect others --

    function test_MultiIndexer_RevokeIsolation() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Revoke indexer1's agreement
        vm.prank(operator);
        agreementManager.revokeOffer(id1);

        // Indexer1 cleared
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);

        // Indexer2 unaffected
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);
        assertEq(agreementManager.getProviderAgreementCount(indexer2), 1);
    }

    // -- Isolation: remove one indexer doesn't affect others --

    function test_MultiIndexer_RemoveIsolation() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // SP cancels indexer1, remove it
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        // Indexer1 cleared
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);

        // Indexer2 unaffected
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);
    }

    // -- Isolation: reconcile one indexer doesn't affect others --

    function test_MultiIndexer_ReconcileIsolation() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Accept and cancel indexer1's agreement by SP
        _setAgreementCanceledBySP(id1, rca1);

        // Reconcile only indexer1
        agreementManager.reconcileAgreement(id1);

        // Indexer1 required escrow drops to 0 (CanceledBySP -> maxNextClaim=0)
        assertEq(agreementManager.getRequiredEscrow(indexer), 0);

        // Indexer2 completely unaffected (still pre-offered estimate)
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);
        assertEq(agreementManager.getAgreementMaxNextClaim(id2), maxClaim2);
    }

    // -- Multiple agreements per indexer --

    function test_MultiIndexer_MultipleAgreementsPerIndexer() public {
        // Two agreements for indexer, one for indexer2
        IRecurringCollector.RecurringCollectionAgreement memory rca1a = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca1b = _makeRCAForIndexer(
            indexer,
            50 ether,
            0.5 ether,
            1800,
            2
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            3
        );

        bytes16 id1a = _offerAgreement(rca1a);
        _offerAgreement(rca1b);
        _offerAgreement(rca2);

        uint256 maxClaim1a = 1 ether * 3600 + 100 ether;
        uint256 maxClaim1b = 0.5 ether * 1800 + 50 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        assertEq(agreementManager.getProviderAgreementCount(indexer), 2);
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1a + maxClaim1b);
        assertEq(agreementManager.getProviderAgreementCount(indexer2), 1);
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);

        // Remove one of indexer's agreements
        _setAgreementCanceledBySP(id1a, rca1a);
        agreementManager.removeAgreement(id1a);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1b);

        // Indexer2 still unaffected
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);
    }

    // -- Cancel one indexer, reconcile another --

    function test_MultiIndexer_CancelAndReconcileIndependently() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        // Accept both
        _setAgreementAccepted(id1, rca1, uint64(block.timestamp));
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        // Cancel indexer1's agreement via operator
        vm.prank(operator);
        agreementManager.cancelAgreement(id1);

        // Indexer1's required escrow updated by cancelAgreement's inline reconcile
        // (still has maxNextClaim from RC since it's CanceledByPayer not CanceledBySP)
        // But the mock just calls SubgraphService — the RC state doesn't change automatically.
        // The cancelAgreement reconciles against whatever the mock RC says.

        // Reconcile indexer2 independently
        agreementManager.reconcileAgreement(id2);

        // Both indexers tracked independently
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
        assertEq(agreementManager.getProviderAgreementCount(indexer2), 1);
    }

    // -- Maintain isolation --

    function test_MultiIndexer_MaintainOnlyAffectsTargetIndexer() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Remove indexer1's agreement
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        // Update escrow for indexer1 — should thaw excess
        agreementManager.updateEscrow(indexer);

        // Indexer1 escrow thawing (excess = maxClaim1, required = 0)
        IPaymentsEscrow.EscrowAccount memory acct1 = paymentsEscrow.getEscrowAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(acct1.balance - acct1.tokensThawing, 0);

        // Indexer2 escrow completely unaffected
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer2).balance,
            maxClaim2
        );

        // updateEscrow on indexer2 is a no-op (balance == required, no excess)
        agreementManager.updateEscrow(indexer2);
    }

    // -- Full lifecycle across multiple indexers --

    function test_MultiIndexer_FullLifecycle() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // 1. Offer both
        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        assertEq(agreementManager.getRequiredEscrow(indexer), maxClaim1);
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);

        // 2. Accept both
        _setAgreementAccepted(id1, rca1, uint64(block.timestamp));
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        // 3. Simulate collection on indexer1 (reduce remaining window)
        uint64 collectionTime = uint64(block.timestamp + 1800);
        _setAgreementCollected(id1, rca1, uint64(block.timestamp), collectionTime);
        vm.warp(collectionTime);

        // 4. Reconcile indexer1 — required should decrease (no more initial tokens)
        agreementManager.reconcileAgreement(id1);
        assertTrue(agreementManager.getRequiredEscrow(indexer) < maxClaim1);

        // Indexer2 unaffected
        assertEq(agreementManager.getRequiredEscrow(indexer2), maxClaim2);

        // 5. Cancel indexer2 by SP
        _setAgreementCanceledBySP(id2, rca2);
        agreementManager.reconcileAgreement(id2);
        assertEq(agreementManager.getRequiredEscrow(indexer2), 0);

        // 6. Remove indexer2's agreement
        agreementManager.removeAgreement(id2);
        assertEq(agreementManager.getProviderAgreementCount(indexer2), 0);

        // 7. Update escrow for indexer2 (thaw excess)
        agreementManager.updateEscrow(indexer2);
        IPaymentsEscrow.EscrowAccount memory acct2 = paymentsEscrow.getEscrowAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );
        assertEq(acct2.balance - acct2.tokensThawing, 0);

        // 8. Indexer1 still active
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
        assertTrue(0 < agreementManager.getRequiredEscrow(indexer));
    }

    // -- getAgreementInfo across indexers --

    function test_MultiIndexer_GetAgreementInfo() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        IServiceAgreementManager.AgreementInfo memory info1 = agreementManager.getAgreementInfo(id1);
        IServiceAgreementManager.AgreementInfo memory info2 = agreementManager.getAgreementInfo(id2);

        assertEq(info1.provider, indexer);
        assertEq(info2.provider, indexer2);
        assertTrue(info1.provider != address(0));
        assertTrue(info2.provider != address(0));
        assertEq(info1.maxNextClaim, 1 ether * 3600 + 100 ether);
        assertEq(info2.maxNextClaim, 2 ether * 7200 + 200 ether);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
