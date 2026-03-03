// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

contract RecurringAgreementHelperAuditTest is RecurringAgreementManagerSharedTest {
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

    function _makeRCAForCollector(
        MockRecurringCollector collector,
        address provider,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca) {
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
    }

    function _offerForCollector(
        MockRecurringCollector collector,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        return agreementManager.offerAgreement(rca, IRecurringCollector(address(collector)));
    }

    // -- Tests: auditGlobal --

    function test_AuditGlobal_EmptyState() public view {
        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(g.tokenBalance, 0);
        assertEq(g.sumMaxNextClaimAll, 0);
        assertEq(g.totalEscrowDeficit, 0);
        assertEq(g.totalAgreementCount, 0);
        assertEq(uint256(g.escrowBasis), uint256(IRecurringEscrowManagement.EscrowBasis.Full));
        assertFalse(g.tempJit);
        assertEq(g.collectorCount, 0);
    }

    function test_AuditGlobal_WithAgreements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(g.sumMaxNextClaimAll, maxClaim);
        assertEq(g.totalAgreementCount, 1);
        assertEq(g.collectorCount, 1);
        // Token balance is the minted amount minus what was deposited to escrow
        assertTrue(0 < g.tokenBalance);
    }

    function test_AuditGlobal_MultiCollector() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(collector2, indexer, 2);
        _offerForCollector(collector2, rca2);

        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(g.totalAgreementCount, 2);
        assertEq(g.collectorCount, 2);
    }

    // -- Tests: auditPair --

    function test_AuditPair_NonExistent() public view {
        IRecurringAgreementHelper.PairAudit memory p = agreementHelper.auditPair(address(recurringCollector), indexer);
        assertEq(p.collector, address(recurringCollector));
        assertEq(p.provider, indexer);
        assertEq(p.agreementCount, 0);
        assertEq(p.sumMaxNextClaim, 0);
        assertEq(p.escrow.balance, 0);
    }

    function test_AuditPair_WithAgreement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        IRecurringAgreementHelper.PairAudit memory p = agreementHelper.auditPair(address(recurringCollector), indexer);
        assertEq(p.agreementCount, 1);
        assertEq(p.sumMaxNextClaim, maxClaim);
        assertEq(p.escrow.balance, maxClaim); // Full mode deposits all
    }

    function test_AuditPair_EscrowThawing() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Cancel by SP to make maxNextClaim = 0, then reconcile (thaw starts)
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        IRecurringAgreementHelper.PairAudit memory p = agreementHelper.auditPair(address(recurringCollector), indexer);
        // sumMaxNextClaim should be 0 after reconcile
        assertEq(p.sumMaxNextClaim, 0);
        // Escrow should be thawing
        assertTrue(0 < p.escrow.tokensThawing);
    }

    // -- Tests: auditPairs --

    function test_AuditPairs_EmptyCollector() public view {
        IRecurringAgreementHelper.PairAudit[] memory pairs = agreementHelper.auditPairs(address(recurringCollector));
        assertEq(pairs.length, 0);
    }

    function test_AuditPairs_MultiplePairs() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(
            recurringCollector,
            indexer2,
            2
        );
        _offerAgreement(rca2);

        IRecurringAgreementHelper.PairAudit[] memory pairs = agreementHelper.auditPairs(address(recurringCollector));
        assertEq(pairs.length, 2);
        // Both should have agreementCount = 1
        assertEq(pairs[0].agreementCount, 1);
        assertEq(pairs[1].agreementCount, 1);
    }

    function test_AuditPairs_Paginated() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(
            recurringCollector,
            indexer2,
            2
        );
        _offerAgreement(rca2);

        // First page
        IRecurringAgreementHelper.PairAudit[] memory first = agreementHelper.auditPairs(
            address(recurringCollector),
            0,
            1
        );
        assertEq(first.length, 1);

        // Second page
        IRecurringAgreementHelper.PairAudit[] memory second = agreementHelper.auditPairs(
            address(recurringCollector),
            1,
            1
        );
        assertEq(second.length, 1);

        // Past end
        IRecurringAgreementHelper.PairAudit[] memory empty = agreementHelper.auditPairs(
            address(recurringCollector),
            2,
            1
        );
        assertEq(empty.length, 0);
    }

    function test_AuditPairs_IsolatesCollectors() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(collector2, indexer, 2);
        _offerForCollector(collector2, rca2);

        IRecurringAgreementHelper.PairAudit[] memory c1Pairs = agreementHelper.auditPairs(address(recurringCollector));
        assertEq(c1Pairs.length, 1);

        IRecurringAgreementHelper.PairAudit[] memory c2Pairs = agreementHelper.auditPairs(address(collector2));
        assertEq(c2Pairs.length, 1);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
