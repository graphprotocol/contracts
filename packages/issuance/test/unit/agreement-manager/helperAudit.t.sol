// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import {
    IAgreementCollector,
    REGISTERED,
    ACCEPTED,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
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
            conditions: 0,
            minSecondsPayerCancellationNotice: 0,
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

    // -- Tests: auditGlobal --

    function test_AuditGlobal_EmptyState() public view {
        IRecurringAgreementHelper.GlobalAudit memory g = agreementHelper.auditGlobal();
        assertEq(g.tokenBalance, 0);
        assertEq(g.sumMaxNextClaimAll, 0);
        assertEq(g.totalEscrowDeficit, 0);
        assertEq(uint256(g.escrowBasis), uint256(IRecurringEscrowManagement.EscrowBasis.Full));
        assertEq(g.minOnDemandBasisThreshold, 128);
        assertEq(g.minFullBasisMargin, 16);
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
        assertEq(g.collectorCount, 2);
    }

    // -- Tests: auditProvider --

    function test_AuditPair_NonExistent() public view {
        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(address(p.collector), address(recurringCollector));
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

        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        IRecurringAgreementHelper.ProviderAudit memory p = agreementHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer);
        // sumMaxNextClaim should be 0 after reconcile
        assertEq(p.sumMaxNextClaim, 0);
        // Escrow should be thawing
        assertTrue(0 < p.escrow.tokensThawing);
    }

    // -- Tests: auditProviders --

    function test_AuditPairs_EmptyCollector() public view {
        IRecurringAgreementHelper.ProviderAudit[] memory pairs = agreementHelper.auditProviders(IAgreementCollector(address(recurringCollector)));
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

        IRecurringAgreementHelper.ProviderAudit[] memory pairs = agreementHelper.auditProviders(IAgreementCollector(address(recurringCollector)));
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
        IRecurringAgreementHelper.ProviderAudit[] memory first = agreementHelper.auditProviders(
            IAgreementCollector(address(recurringCollector)),
            0,
            1
        );
        assertEq(first.length, 1);

        // Second page
        IRecurringAgreementHelper.ProviderAudit[] memory second = agreementHelper.auditProviders(
            IAgreementCollector(address(recurringCollector)),
            1,
            1
        );
        assertEq(second.length, 1);

        // Past end
        IRecurringAgreementHelper.ProviderAudit[] memory empty = agreementHelper.auditProviders(
            IAgreementCollector(address(recurringCollector)),
            2,
            1
        );
        assertEq(empty.length, 0);
    }

    // -- Tests: getProviderAgreements (paginated) --

    function test_GetProviderAgreements_Paginated() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            2
        );
        _offerAgreement(rca2);

        // Full list
        bytes16[] memory all = agreementHelper.getAgreements(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(all.length, 2);

        // First page
        bytes16[] memory first = agreementHelper.getAgreements(IAgreementCollector(address(recurringCollector)), indexer, 0, 1);
        assertEq(first.length, 1);
        assertEq(first[0], all[0]);

        // Second page
        bytes16[] memory second = agreementHelper.getAgreements(IAgreementCollector(address(recurringCollector)), indexer, 1, 1);
        assertEq(second.length, 1);
        assertEq(second[0], all[1]);

        // Past end
        bytes16[] memory empty = agreementHelper.getAgreements(IAgreementCollector(address(recurringCollector)), indexer, 2, 1);
        assertEq(empty.length, 0);

        // Count larger than remaining
        bytes16[] memory clamped = agreementHelper.getAgreements(IAgreementCollector(address(recurringCollector)), indexer, 1, 100);
        assertEq(clamped.length, 1);
        assertEq(clamped[0], all[1]);
    }

    // -- Tests: getCollectors (paginated) --

    function test_GetCollectors_Paginated() public {
        // Create agreements under two different collectors to register them
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForCollector(
            recurringCollector,
            indexer,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForCollector(collector2, indexer, 2);
        _offerForCollector(collector2, rca2);

        // Full list
        address[] memory all = agreementHelper.getCollectors();
        assertEq(all.length, 2);

        // First page
        address[] memory first = agreementHelper.getCollectors(0, 1);
        assertEq(first.length, 1);
        assertEq(first[0], all[0]);

        // Second page
        address[] memory second = agreementHelper.getCollectors(1, 1);
        assertEq(second.length, 1);
        assertEq(second[0], all[1]);

        // Past end
        address[] memory empty = agreementHelper.getCollectors(2, 1);
        assertEq(empty.length, 0);

        // Count larger than remaining
        address[] memory clamped = agreementHelper.getCollectors(1, 100);
        assertEq(clamped.length, 1);
        assertEq(clamped[0], all[1]);
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

        IRecurringAgreementHelper.ProviderAudit[] memory c1Pairs = agreementHelper.auditProviders(IAgreementCollector(address(recurringCollector)));
        assertEq(c1Pairs.length, 1);

        IRecurringAgreementHelper.ProviderAudit[] memory c2Pairs = agreementHelper.auditProviders(IAgreementCollector(address(collector2)));
        assertEq(c2Pairs.length, 1);
    }

    // -- checkStaleness --

    function test_CheckPairStaleness_DetectsStaleAgreement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        token.mint(address(agreementManager), 1_000_000 ether);
        bytes16 agreementId = _offerAgreement(rca);

        // Fresh state: cached == live
        (IRecurringAgreementHelper.AgreementStaleness[] memory stale, bool escrowStale) =
            agreementHelper.checkStaleness(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(stale.length, 1);
        assertEq(stale[0].agreementId, agreementId);
        assertFalse(stale[0].stale, "Should not be stale when cached == live");

        // Make it stale: modify the collector's agreement so getMaxNextClaim diverges
        MockRecurringCollector.AgreementStorage memory mockData = _buildAgreementStorage(
            rca, REGISTERED | ACCEPTED, uint64(block.timestamp), rca.endsAt, 0
        );
        mockData.activeTerms.maxOngoingTokensPerSecond = 2 ether; // double the rate
        recurringCollector.setAgreement(agreementId, mockData);

        // Now cached != live
        (stale, escrowStale) = agreementHelper.checkStaleness(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(stale.length, 1);
        assertTrue(stale[0].stale, "Should be stale when collector rate changed");
        assertTrue(stale[0].liveMaxNextClaim > stale[0].cachedMaxNextClaim);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
