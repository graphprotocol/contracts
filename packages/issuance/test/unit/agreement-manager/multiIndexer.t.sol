// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerMultiIndexerTest is RecurringAgreementManagerSharedTest {
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

    // -- Isolation: offer/sumMaxNextClaim --

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

        // Each indexer has independent sumMaxNextClaim
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer3), maxClaim3);

        // Each has exactly 1 agreement
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer2), 1);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer3), 1);

        // Each has independent escrow balance
        (uint256 indexerBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(indexerBalance, maxClaim1);
        (uint256 indexer2Balance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );
        assertEq(indexer2Balance, maxClaim2);
        (uint256 indexer3Balance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer3
        );
        assertEq(indexer3Balance, maxClaim3);
    }

    // -- Isolation: revoke one indexer doesn't affect others --

    function test_MultiIndexer_CancelIsolation() public {
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

        // Cancel indexer1's agreement
        _cancelAgreement(id1);

        // Indexer1 cleared
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);

        // Indexer2 unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer2), 1);
    }

    // -- Isolation: reconcile one indexer doesn't affect others --

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

        // SP cancels indexer1, reconcile it
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);

        // Indexer1 cleared
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);

        // Indexer2 unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);

        // Indexer1 required escrow drops to 0 (CanceledBySP -> maxNextClaim=0)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);

        // Indexer2 completely unaffected (still pre-offered estimate)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), id2),
            maxClaim2
        );
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

        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 2);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1a + maxClaim1b);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer2), 1);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);

        // Reconcile one of indexer's agreements
        _setAgreementCanceledBySP(id1a, rca1a);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1a);

        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1b);

        // Indexer2 still unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);
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

        // Advance time so CanceledByPayer has a non-zero claim window
        vm.warp(block.timestamp + 10);

        // Cancel indexer1's agreement via operator — collector.cancel() sets CanceledByPayer
        _cancelAgreement(id1);

        // Reconcile indexer2 independently
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id2);

        // Both indexers tracked independently — id1 still has remaining claim window
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer2), 1);
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

        // Reconcile indexer1's agreement
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);

        // Update escrow for indexer1 — should thaw excess
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        // Indexer1 escrow thawing (excess = maxClaim1, required = 0)
        IPaymentsEscrow.EscrowAccount memory acct1;
        (acct1.balance, acct1.tokensThawing, acct1.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(acct1.balance - acct1.tokensThawing, 0);

        // Indexer2 escrow completely unaffected
        (uint256 indexer2Bal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );
        assertEq(indexer2Bal, maxClaim2);

        // reconcileProvider on indexer2 is a no-op (balance == required, no excess)
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer2);
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

        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);

        // 2. Accept both
        _setAgreementAccepted(id1, rca1, uint64(block.timestamp));
        _setAgreementAccepted(id2, rca2, uint64(block.timestamp));

        // 3. Simulate collection on indexer1 (reduce remaining window)
        uint64 collectionTime = uint64(block.timestamp + 1800);
        _setAgreementCollected(id1, rca1, uint64(block.timestamp), collectionTime);
        vm.warp(collectionTime);

        // 4. Reconcile indexer1 — required should decrease (no more initial tokens)
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);
        assertTrue(agreementManager.getSumMaxNextClaim(_collector(), indexer) < maxClaim1);

        // Indexer2 unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2);

        // 5. Cancel indexer2 by SP
        _setAgreementCanceledBySP(id2, rca2);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id2);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), 0);

        // 6. Reconcile indexer2's agreement
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id2);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer2), 0);

        // 7. Update escrow for indexer2 (thaw excess)
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer2);
        IPaymentsEscrow.EscrowAccount memory acct2;
        (acct2.balance, acct2.tokensThawing, acct2.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );
        assertEq(acct2.balance - acct2.tokensThawing, 0);

        // 8. Indexer1 still active
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertTrue(0 < agreementManager.getSumMaxNextClaim(_collector(), indexer));
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

        IRecurringAgreements.AgreementInfo memory info1 = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            id1
        );
        IRecurringAgreements.AgreementInfo memory info2 = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            id2
        );

        assertEq(info1.provider, indexer);
        assertEq(info2.provider, indexer2);
        assertTrue(info1.provider != address(0));
        assertTrue(info2.provider != address(0));
        assertEq(info1.maxNextClaim, 1 ether * 3600 + 100 ether);
        assertEq(info2.maxNextClaim, 2 ether * 7200 + 200 ether);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
