// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_UPDATE,
    SCOPE_ACTIVE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { PPMMath } from "horizon/libraries/PPMMath.sol";

import { IndexingAgreement } from "subgraph-service/libraries/IndexingAgreement.sol";

import { FullStackHarness } from "../harness/FullStackHarness.t.sol";

/// @title AgreementLifecycleTest
/// @notice End-to-end integration tests exercising the full indexing agreement lifecycle
/// through real RAM, RecurringCollector, SubgraphService, GraphPayments, and PaymentsEscrow.
contract AgreementLifecycleTest is FullStackHarness {
    using PPMMath for uint256;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT = keccak256("test-subgraph-deployment");
    uint256 internal constant INDEXER_TOKENS = 10_000 ether;

    IndexerSetup internal indexer;

    function setUp() public override {
        super.setUp();
        indexer = _setupIndexer("indexer1", SUBGRAPH_DEPLOYMENT, INDEXER_TOKENS);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 1: Happy path — Offer → Accept → Collect → Reconcile
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario1_OfferAcceptCollectReconcile() public {
        // -- Parameters --
        uint256 maxInitial = 100 ether;
        uint256 maxOngoing = 1 ether; // 1 token/sec
        uint32 maxSecPerCollection = 3600; // 1 hour
        uint256 tokensPerSecond = 0.5 ether; // agreement rate (terms)
        uint256 expectedMaxClaim = maxOngoing * maxSecPerCollection + maxInitial;

        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: tokensPerSecond,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(
            indexer,
            maxInitial,
            maxOngoing,
            maxSecPerCollection,
            terms
        );

        // -- Step 1: RAM offers agreement --
        bytes16 agreementId = _ramOffer(rca);

        // Verify RAM tracks the agreement with escrow deposited (Full mode)
        IRecurringAgreementHelper.ProviderAudit memory pAudit = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertEq(pAudit.sumMaxNextClaim, expectedMaxClaim, "maxNextClaim after offer");
        assertEq(pAudit.escrow.balance, expectedMaxClaim, "escrow deposited in Full mode");

        // -- Step 2: Accept via SubgraphService --
        bytes16 acceptedId = _ssAccept(indexer, rca);
        assertEq(acceptedId, agreementId, "agreement ID matches");

        // Verify RC stored the agreement
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(uint8(rcAgreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
        assertEq(rcAgreement.payer, address(ram));
        assertEq(rcAgreement.serviceProvider, indexer.addr);

        // Verify SS stored the agreement
        IIndexingAgreement.AgreementWrapper memory ssAgreement = subgraphService.getIndexingAgreement(agreementId);
        assertEq(uint8(ssAgreement.collectorAgreement.state), uint8(IRecurringCollector.AgreementState.Accepted));

        // -- Step 3: Advance time and collect --
        uint256 collectSeconds = 1800; // 30 minutes
        skip(collectSeconds);

        // Add extra tokens to indexer's provision for stake locking
        uint256 expectedTokens = tokensPerSecond * collectSeconds;
        uint256 tokensToLock = expectedTokens * STAKE_TO_FEES_RATIO;
        _mintTokens(indexer.addr, tokensToLock);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), tokensToLock);
        staking.stakeTo(indexer.addr, tokensToLock);
        staking.addToProvision(indexer.addr, address(subgraphService), tokensToLock);
        vm.stopPrank();

        uint256 indexerBalanceBefore = token.balanceOf(indexer.addr);
        (uint256 escrowBefore, , ) = escrow.escrowAccounts(address(ram), address(recurringCollector), indexer.addr);

        // Advance past allocation creation epoch so POI isn't "too young"
        vm.roll(block.number + EPOCH_LENGTH);

        uint256 tokensCollected = _collectIndexingFees(
            indexer,
            agreementId,
            0, // entities
            keccak256("poi1"),
            block.number - 1
        );

        // Verify tokens flowed correctly
        assertTrue(tokensCollected > 0, "should collect tokens");
        uint256 indexerBalanceAfter = token.balanceOf(indexer.addr);
        uint256 protocolBurn = tokensCollected.mulPPMRoundUp(PROTOCOL_PAYMENT_CUT);
        assertEq(
            indexerBalanceAfter - indexerBalanceBefore,
            tokensCollected - protocolBurn,
            "indexer received tokens minus protocol cut"
        );

        // Verify escrow changed (RAM's beforeCollection/afterCollection may adjust balance)
        (uint256 escrowAfter, , ) = escrow.escrowAccounts(address(ram), address(recurringCollector), indexer.addr);
        assertTrue(escrowAfter < escrowBefore, "escrow balance decreased after collection");

        // -- Step 4: Reconcile RAM state --
        ram.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        // After first collection, maxInitialTokens drops out
        uint256 expectedMaxClaimAfterCollection = maxOngoing * maxSecPerCollection;
        assertEq(pAudit.sumMaxNextClaim, expectedMaxClaimAfterCollection, "maxNextClaim reduced after collection");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 2: Update flow — Offer → Accept → Update → Collect
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario2_UpdateFlow() public {
        uint256 tokensPerSecond = 0.5 ether;
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: tokensPerSecond,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 2 ether, 3600, terms);

        // Offer + accept
        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Build update with higher rate
        uint256 newTokensPerSecond = 1 ether;
        IndexingAgreement.IndexingAgreementTermsV1 memory newTerms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: newTokensPerSecond,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                nonce: 1,
                conditions: 0,
                metadata: abi.encode(
                    IndexingAgreement.UpdateIndexingAgreementMetadata({
                        version: IIndexingAgreement.IndexingAgreementVersion.V1,
                        terms: abi.encode(newTerms)
                    })
                )
            });

        // RAM offers update
        vm.prank(operator);
        ram.offerAgreement(IAgreementCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));

        // SS accepts update
        vm.prank(indexer.addr);
        subgraphService.updateIndexingAgreement(indexer.addr, rcau, "");

        // Advance time and collect at new rate
        uint256 collectSeconds = 1800;
        skip(collectSeconds);

        uint256 expectedTokens = newTokensPerSecond * collectSeconds;
        uint256 tokensToLock = expectedTokens * STAKE_TO_FEES_RATIO;
        _mintTokens(indexer.addr, tokensToLock);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), tokensToLock);
        staking.stakeTo(indexer.addr, tokensToLock);
        staking.addToProvision(indexer.addr, address(subgraphService), tokensToLock);
        vm.stopPrank();

        vm.roll(block.number + EPOCH_LENGTH);

        uint256 tokensCollected = _collectIndexingFees(indexer, agreementId, 0, keccak256("poi2"), block.number - 1);

        // At 1 token/sec for 1800 sec, we expect ~1800 tokens
        // (capped by maxOngoingTokensPerSecond * collectSeconds = 2 * 1800 = 3600)
        assertTrue(tokensCollected > 0, "should collect tokens at updated rate");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 3: Cancel by indexer → Reconcile → Escrow cleanup
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario3_CancelByIndexerAndCleanup() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(
            indexer,
            100 ether,
            1 ether,
            3600,
            terms
        );
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Verify escrow deposited
        IRecurringAgreementHelper.ProviderAudit memory pAudit = ramHelper.auditProvider(
            IAgreementCollector(address(recurringCollector)),
            indexer.addr
        );
        assertEq(pAudit.escrow.balance, expectedMaxClaim, "escrow deposited");

        // Cancel by indexer via SubgraphService
        vm.prank(indexer.addr);
        subgraphService.cancelIndexingAgreement(indexer.addr, agreementId);

        // Verify RC state
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByServiceProvider),
            "RC: canceled by SP"
        );

        // Reconcile RAM — removes agreement, starts thawing escrow
        ram.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        IRecurringAgreementHelper.GlobalAudit memory gAudit = ramHelper.auditGlobal();
        assertEq(gAudit.sumMaxNextClaimAll, 0, "global maxNextClaim zeroed");

        // Escrow is thawing
        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertTrue(pAudit.escrow.tokensThawing > 0, "escrow should be thawing");

        // Wait for thaw and withdraw
        skip(1 days + 1); // WITHDRAW_ESCROW_THAWING_PERIOD is 60s but PaymentsEscrow uses 1 day
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        pAudit = ramHelper.auditProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);
        assertEq(pAudit.escrow.balance, 0, "escrow drained after thaw");
        assertEq(pAudit.escrow.tokensThawing, 0, "no more thawing");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 4: Cancel by payer (scoped) via RC callback chain
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario4_ScopedCancelByPayer() public {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(
            indexer,
            100 ether,
            1 ether,
            3600,
            terms
        );

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // Read activeTermsHash for scoped cancel
        IRecurringCollector.AgreementData memory rcAgreement = recurringCollector.getAgreement(agreementId);
        bytes32 activeTermsHash = rcAgreement.activeTermsHash;
        assertTrue(activeTermsHash != bytes32(0), "activeTermsHash should be set");

        // Payer (RAM) calls RC's scoped cancel → triggers SS cancelByPayer callback
        // RAM is the payer, so it must make the call
        vm.prank(address(ram));
        recurringCollector.cancel(agreementId, activeTermsHash, SCOPE_ACTIVE);

        // Verify RC state: CanceledByPayer
        rcAgreement = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(rcAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByPayer),
            "RC: canceled by payer"
        );

        // Verify SS state reflects cancellation
        IIndexingAgreement.AgreementWrapper memory ssAgreement = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            uint8(ssAgreement.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByPayer),
            "SS: reflects payer cancellation"
        );

        // Reconcile RAM
        ram.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        IRecurringAgreementHelper.GlobalAudit memory gAudit = ramHelper.auditGlobal();
        assertEq(gAudit.sumMaxNextClaimAll, 0, "global maxNextClaim zeroed after payer cancel");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Scenario 5: JIT top-up — Low escrow → Collect triggers deposit
    // ═══════════════════════════════════════════════════════════════════

    function test_Scenario5_JITTopUp() public {
        // Switch RAM to JustInTime escrow basis — no proactive deposits
        vm.prank(operator);
        ram.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 0.5 ether,
            tokensPerEntityPerSecond: 0
        });

        IRecurringCollector.RecurringCollectionAgreement memory rca = _buildRCA(indexer, 0, 1 ether, 3600, terms);

        bytes16 agreementId = _offerAndAccept(indexer, rca);

        // In JIT mode, reconcileProvider should thaw everything
        ram.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer.addr);

        // Advance time for collection
        uint256 collectSeconds = 600; // 10 minutes
        skip(collectSeconds);

        // Add provision tokens for stake locking
        uint256 expectedTokens = terms.tokensPerSecond * collectSeconds;
        uint256 tokensToLock = expectedTokens * STAKE_TO_FEES_RATIO;
        _mintTokens(indexer.addr, tokensToLock);
        vm.startPrank(indexer.addr);
        token.approve(address(staking), tokensToLock);
        staking.stakeTo(indexer.addr, tokensToLock);
        staking.addToProvision(indexer.addr, address(subgraphService), tokensToLock);
        vm.stopPrank();

        vm.roll(block.number + EPOCH_LENGTH);

        // Collect — this triggers RC.collect → RAM.beforeCollection (JIT deposit) → payment
        uint256 tokensCollected = _collectIndexingFees(indexer, agreementId, 0, keccak256("poi-jit"), block.number - 1);

        // Verify collection succeeded despite JIT mode (beforeCollection topped up escrow)
        assertTrue(tokensCollected > 0, "JIT: collection should succeed");

        // Indexer should have received tokens
        uint256 protocolBurn = tokensCollected.mulPPMRoundUp(PROTOCOL_PAYMENT_CUT);
        assertTrue(tokensCollected - protocolBurn > 0, "JIT: indexer received tokens");
    }
}
