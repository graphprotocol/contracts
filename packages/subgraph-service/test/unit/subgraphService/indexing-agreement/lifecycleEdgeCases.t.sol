// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    REGISTERED,
    ACCEPTED,
    SETTLED,
    NOTICE_GIVEN,
    BY_PAYER,
    BY_PROVIDER,
    UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

/// @title Lifecycle Edge Case Tests
/// @notice Tests for edge cases identified during audit review:
///   - Agreement expiration without collection (audit gap 5)
///   - Collection during payer cancellation notice period (audit gap 7)
///   - Sequential update stacking -- replacing pending updates (audit gap 8)
///   - Multi-cycle revival chain with full state verification (audit gap 9)
///   - Callback revert on accept rolls back cleanly (audit gap 14)
///   - Notice period shorter than minSecondsPerCollection (audit gap 15)
contract LifecycleEdgeCasesTest is SubgraphServiceIndexingAgreementSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Fund payer's escrow for the (recurringCollector, indexer) pair
    function _setupPayerWithEscrow(address _payer, address _indexer, uint256 _tokens) internal {
        deal({ token: address(token), to: _payer, give: _tokens });
        vm.startPrank(_payer);
        token.approve(address(escrow), _tokens);
        escrow.deposit(address(recurringCollector), _indexer, _tokens);
        vm.stopPrank();
    }

    /// @dev Add provision capacity so fee locking succeeds during collection
    function _addTokensToProvision(IndexerState memory _indexer, uint256 _tokens) internal {
        deal({ token: address(token), to: _indexer.addr, give: _tokens });
        vm.startPrank(_indexer.addr);
        _addToProvision(_indexer.addr, _tokens);
        vm.stopPrank();
    }

    /// @dev Create an accepted agreement with controlled timing parameters.
    ///      Calls sensibleRCA first (to get valid bounded fields), then overrides
    ///      timing params. Optionally funds escrow.
    function _withControlledAgreement(
        Context storage _ctx,
        IndexerState memory _indexer,
        uint64 _endsAt,
        uint32 _minSecondsPerCollection,
        uint32 _maxSecondsPerCollection,
        uint32 _minSecondsPayerCancellationNotice,
        uint256 _maxOngoingTokensPerSecond,
        uint256 _escrowAmount
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 1,
            tokensPerEntityPerSecond: 0
        });

        // Get sensible defaults from fuzz seed, then override what we need
        rca = _recurringCollectorHelper.sensibleRCA(_ctx.ctxInternal.seed.rca);
        rca.serviceProvider = _indexer.addr;
        rca.dataService = address(subgraphService);
        rca.metadata = _encodeAcceptIndexingAgreementMetadataV1(_indexer.subgraphDeploymentId, terms);
        rca.deadline = uint64(block.timestamp + 1 hours);
        rca.endsAt = _endsAt;
        rca.minSecondsPerCollection = _minSecondsPerCollection;
        rca.maxSecondsPerCollection = _maxSecondsPerCollection;
        rca.minSecondsPayerCancellationNotice = _minSecondsPayerCancellationNotice;
        rca.maxOngoingTokensPerSecond = _maxOngoingTokensPerSecond;
        rca.maxInitialTokens = 0;

        // Exclude addresses that would conflict with protocol contracts, proxy admins, or test users.
        // Full _isSafeSubgraphServiceCaller check is needed because the payer interacts with
        // proxied contracts (token.approve, escrow.deposit) and would trigger ProxyDeniedAdminAccess.
        vm.assume(_isSafeSubgraphServiceCaller(rca.payer));
        vm.assume(!_isTestUser(rca.payer));
        vm.assume(rca.payer != _indexer.addr);

        if (_escrowAmount > 0) {
            _setupPayerWithEscrow(rca.payer, _indexer.addr, _escrowAmount);
        }

        // Offer
        vm.prank(rca.payer);
        agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Accept
        bytes32 versionHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(_indexer.addr);
        recurringCollector.accept(agreementId, versionHash, abi.encode(_indexer.allocationId), 0);
    }

    /// @dev Collect indexing fees with a simple 1-entity POI
    function _collectIndexingFees(address _indexer, bytes16 _agreementId) internal returns (uint256) {
        return
            subgraphService.collect(
                _indexer,
                IGraphPayments.PaymentTypes.IndexingFee,
                _encodeCollectDataV1(_agreementId, 1, keccak256("poi"), epochManager.currentEpochBlock(), bytes(""))
            );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  5. Agreement expiration without collection
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Agreement accepted but never collected -- after endsAt, state is still
    ///         ACCEPTED (not auto-settled) and a final collection is possible.
    function test_ExpirationWithoutCollection_StillCollectable(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        uint64 endsAt = uint64(block.timestamp + 1 hours);
        (, bytes16 agreementId) = _withControlledAgreement(
            ctx,
            indexer,
            endsAt,
            60, // minSecondsPerCollection
            3600, // maxSecondsPerCollection
            0, // no cancellation notice
            1 ether, // maxOngoingTokensPerSecond
            0 // no escrow (state check only)
        );

        // Warp past endsAt
        vm.warp(endsAt + 1);

        IRecurringCollector.AgreementData memory data = recurringCollector.getAgreementData(agreementId);
        assertEq(data.state & ACCEPTED, ACCEPTED, "should still be ACCEPTED after expiry");
        assertEq(data.state & SETTLED, 0, "should NOT be SETTLED without collection trigger");
        assertTrue(data.isCollectable, "should be collectable for final collection after expiry");
        assertEq(data.collectableUntil, endsAt, "collectableUntil should equal endsAt");
    }

    /// @notice Agreement expires → collection after expiry settles it
    function test_ExpirationWithoutCollection_SettlesOnCollect(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        uint64 endsAt = uint64(block.timestamp + 1 hours);
        // 1 token/sec * 3600 sec = 3600 tokens max
        uint256 maxTokens = 3600;
        _addTokensToProvision(indexer, maxTokens * STAKE_TO_FEES_RATIO);

        (, bytes16 agreementId) = _withControlledAgreement(
            ctx,
            indexer,
            endsAt,
            1, // minSecondsPerCollection = 1
            3600, // maxSecondsPerCollection
            0, // no cancellation notice
            1, // 1 token/sec
            maxTokens // escrow
        );

        resetPrank(indexer.addr);
        subgraphService.setPaymentsDestination(indexer.addr);

        // Warp past endsAt
        vm.warp(endsAt + 100);

        // Collect after expiry -- should succeed (minSecondsPerCollection waived past collectableUntil)
        resetPrank(indexer.addr);
        uint256 tokensCollected = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(tokensCollected > 0, "should collect tokens after expiry");

        // Agreement should now be SETTLED (maxNextClaim = 0 after consuming full window)
        IRecurringCollector.AgreementData memory data = recurringCollector.getAgreementData(agreementId);
        assertEq(data.state & SETTLED, SETTLED, "should be SETTLED after final collection past endsAt");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  7. Collection during notice period
    // ══════════════════════════════════════════════════════════════════════

    /// @notice After payer cancel, provider can still collect during the notice window
    function test_CollectDuringNoticePeriod_Succeeds(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        uint256 maxTokens = 100_000;
        _addTokensToProvision(indexer, maxTokens * STAKE_TO_FEES_RATIO);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _withControlledAgreement(
            ctx,
            indexer,
            uint64(block.timestamp + 365 days), // long-running agreement
            60, // minSecondsPerCollection = 60s
            3600, // maxSecondsPerCollection = 1h
            7200, // minSecondsPayerCancellationNotice = 2h
            1, // 1 token/sec
            maxTokens
        );

        resetPrank(indexer.addr);
        subgraphService.setPaymentsDestination(indexer.addr);

        // First collection
        skip(100);
        resetPrank(indexer.addr);
        uint256 firstCollect = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(firstCollect > 0, "first collection should succeed");

        // Payer cancels → NOTICE_GIVEN with 2h notice
        resetPrank(rca.payer);
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        recurringCollector.cancel(agreementId, activeHash, 0);

        IRecurringCollector.AgreementData memory afterCancel = recurringCollector.getAgreementData(agreementId);
        assertEq(afterCancel.state & NOTICE_GIVEN, NOTICE_GIVEN, "should be NOTICE_GIVEN");
        assertEq(afterCancel.state & BY_PAYER, BY_PAYER, "should be BY_PAYER");
        assertEq(afterCancel.state & SETTLED, 0, "should NOT be SETTLED during notice");

        // Provider collects during notice period
        skip(100); // satisfy minSecondsPerCollection (100 > 60)
        resetPrank(indexer.addr);
        uint256 secondCollect = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(secondCollect > 0, "collection during notice period should succeed");

        // Verify tokens from second collection are bounded by collectableUntil, not endsAt
        assertTrue(secondCollect < 3600, "tokens should be bounded (not a full maxSecondsPerCollection window)");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  8. Sequential update stacking
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Offering update nonce=2 before nonce=1 is accepted replaces pending terms
    function test_UpdateStacking_SecondReplacesFirst(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Capture original collectableUntil (== activeTerms.endsAt after accept)
        IRecurringCollector.AgreementData memory original = recurringCollector.getAgreementData(agreementId);
        uint64 originalCollectableUntil = original.collectableUntil;

        // Offer first update (nonce=1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);

        IRecurringCollector.AgreementData memory afterFirst = recurringCollector.getAgreementData(agreementId);
        assertEq(afterFirst.updateNonce, 1, "updateNonce should be 1 after first offer");
        // Active terms unchanged: collectableUntil still reflects original
        assertEq(afterFirst.collectableUntil, originalCollectableUntil, "active terms should be unchanged");
        // Pending version exists
        assertEq(recurringCollector.getAgreementVersionCount(agreementId), 2, "should have active + pending version");

        // Offer second update (nonce=2) with different endsAt
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _generateAcceptableRCAU(ctx, rca);
        rcau2.nonce = 2;
        rcau2.endsAt = rcau1.endsAt + 1 days;

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);

        IRecurringCollector.AgreementData memory afterSecond = recurringCollector.getAgreementData(agreementId);
        assertEq(afterSecond.updateNonce, 2, "updateNonce should be 2 after second offer");
        assertEq(afterSecond.collectableUntil, originalCollectableUntil, "active terms still unchanged");

        // Accept second update -- first is effectively discarded
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        IRecurringCollector.AgreementData memory afterAccept = recurringCollector.getAgreementData(agreementId);
        assertEq(afterAccept.collectableUntil, rcau2.endsAt, "collectableUntil should reflect second update's endsAt");
        assertEq(recurringCollector.getAgreementVersionCount(agreementId), 1, "only active version after accept");
        assertEq(afterAccept.state & ACCEPTED, ACCEPTED, "should be ACCEPTED");
        assertEq(afterAccept.state & SETTLED, 0, "should not be SETTLED");
    }

    /// @notice Accept first update, then offer and accept second -- clean sequential cycle
    function test_UpdateStacking_SequentialAcceptances(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // --- First update cycle ---
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);

        bytes32 hash1 = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, hash1, bytes(""), 0);

        IRecurringCollector.AgreementData memory afterFirst = recurringCollector.getAgreementData(agreementId);
        assertEq(afterFirst.collectableUntil, rcau1.endsAt, "collectableUntil should reflect first update");
        assertEq(recurringCollector.getAgreementVersionCount(agreementId), 1, "only active version after first accept");
        assertEq(afterFirst.state, REGISTERED | ACCEPTED | UPDATE, "state includes UPDATE after accepting update");

        // --- Second update cycle ---
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _generateAcceptableRCAU(ctx, rca);
        rcau2.nonce = 2;
        rcau2.endsAt = rcau1.endsAt + 1 days;

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);

        bytes32 hash2 = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, hash2, bytes(""), 0);

        IRecurringCollector.AgreementData memory afterSecond = recurringCollector.getAgreementData(agreementId);
        assertEq(afterSecond.collectableUntil, rcau2.endsAt, "collectableUntil should reflect second update");
        assertEq(
            recurringCollector.getAgreementVersionCount(agreementId),
            1,
            "only active version after second accept"
        );
        assertEq(afterSecond.state, REGISTERED | ACCEPTED | UPDATE, "state includes UPDATE after sequential updates");
        assertEq(afterSecond.updateNonce, 2, "updateNonce should be 2");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  9. Revival chain -- multi-cycle cancel/revive
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Cancel → revive → cancel → revive, verifying full state word at each step
    function test_RevivalChain_DoubleCycleFullStateVerification(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        uint64 originalAcceptedAt;
        uint64 rcau1EndsAt;

        // ── Step 1: Verify initial ACCEPTED state ──
        {
            IRecurringCollector.AgreementData memory s1 = recurringCollector.getAgreementData(agreementId);
            assertEq(s1.state, REGISTERED | ACCEPTED, "step1: should be REGISTERED|ACCEPTED");
            originalAcceptedAt = s1.acceptedAt;
        }

        // ── Step 2: Cancel by provider → immediate SETTLED ──
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        {
            IRecurringCollector.AgreementData memory s2 = recurringCollector.getAgreementData(agreementId);
            // Provider cancel does NOT immediately set SETTLED — it sets collectableUntil = now
            // so the provider can still collect for work done since lastCollectionAt. SETTLED is
            // set later when the final collection drains the remaining window.
            assertEq(
                s2.state,
                REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER,
                "step2: NOTICE_GIVEN|BY_PROVIDER (not yet SETTLED)"
            );

            // SS-level: allocation should still be bound (provider cancel doesn't clear mappings)
            IIndexingAgreement.AgreementWrapper memory w2 = subgraphService.getIndexingAgreement(agreementId);
            assertEq(w2.agreement.allocationId, indexer.allocationId, "step2: allocation still bound");
        }

        // ── Step 3: Offer update (nonce=1) and accept → first revival ──
        {
            IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _generateAcceptableRCAU(ctx, rca);

            resetPrank(rca.payer);
            recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);

            bytes32 hash1 = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
            resetPrank(indexer.addr);
            recurringCollector.accept(agreementId, hash1, bytes(""), 0);

            IRecurringCollector.AgreementData memory s3 = recurringCollector.getAgreementData(agreementId);
            assertEq(s3.state, REGISTERED | ACCEPTED | UPDATE, "step3: revived -- REGISTERED|ACCEPTED|UPDATE");
            assertEq(s3.state & SETTLED, 0, "step3: SETTLED cleared");
            assertEq(s3.state & NOTICE_GIVEN, 0, "step3: NOTICE_GIVEN cleared");
            assertEq(s3.state & BY_PROVIDER, 0, "step3: BY_PROVIDER cleared");
            assertTrue(s3.acceptedAt >= originalAcceptedAt, "step3: acceptedAt refreshed on revival");
            rcau1EndsAt = rcau1.endsAt;
            assertEq(s3.collectableUntil, rcau1EndsAt, "step3: collectableUntil from first update");

            IIndexingAgreement.AgreementWrapper memory w3 = subgraphService.getIndexingAgreement(agreementId);
            assertEq(w3.agreement.allocationId, indexer.allocationId, "step3: allocation still bound");
        }

        // ── Step 4: Cancel by provider again → SETTLED ──
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        {
            IRecurringCollector.AgreementData memory s4 = recurringCollector.getAgreementData(agreementId);
            // UPDATE persists from the step 3 revival (accepted an update)
            assertEq(
                s4.state,
                REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER | UPDATE,
                "step4: NOTICE_GIVEN|BY_PROVIDER|UPDATE (not yet SETTLED)"
            );
        }

        // ── Step 5: Second revival ──
        {
            IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _generateAcceptableRCAU(ctx, rca);
            rcau2.nonce = 2;

            resetPrank(rca.payer);
            recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);

            bytes32 hash2 = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
            resetPrank(indexer.addr);
            recurringCollector.accept(agreementId, hash2, bytes(""), 0);

            IRecurringCollector.AgreementData memory s5 = recurringCollector.getAgreementData(agreementId);
            assertEq(s5.state, REGISTERED | ACCEPTED | UPDATE, "step5: second revival -- REGISTERED|ACCEPTED|UPDATE");
            assertEq(
                s5.state & (SETTLED | NOTICE_GIVEN | BY_PROVIDER | BY_PAYER),
                0,
                "step5: all cancel flags cleared after second revival"
            );
            assertEq(s5.collectableUntil, rcau2.endsAt, "step5: collectableUntil from second update");
            assertEq(s5.updateNonce, 2, "step5: updateNonce should be 2");

            IIndexingAgreement.AgreementWrapper memory w5 = subgraphService.getIndexingAgreement(agreementId);
            assertEq(w5.agreement.allocationId, indexer.allocationId, "step5: allocation bound after double revival");
        }
    }

    /// @notice After revival, collection actually works (not just state looks right)
    function test_RevivalChain_CollectionWorksAfterRevival(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        uint256 maxTokens = 100_000;
        _addTokensToProvision(indexer, maxTokens * STAKE_TO_FEES_RATIO);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _withControlledAgreement(
            ctx,
            indexer,
            uint64(block.timestamp + 365 days),
            1, // minSecondsPerCollection
            3600, // maxSecondsPerCollection
            0, // no notice
            1, // 1 token/sec
            maxTokens
        );

        resetPrank(indexer.addr);
        subgraphService.setPaymentsDestination(indexer.addr);

        // Collect once before cancel
        skip(100);
        resetPrank(indexer.addr);
        uint256 preRevivalCollect = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(preRevivalCollect > 0, "pre-revival collection should succeed");

        // Cancel by provider → collectableUntil = now
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        // Revive via controlled update with known timing and token rate.
        // Using _generateAcceptableRCAU would re-bound minSecondsPerCollection to >=600s
        // and maxOngoingTokensPerSecond to potentially huge values, making escrow unpredictable.
        IndexingAgreement.IndexingAgreementTermsV1 memory updateTerms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 1,
            tokensPerEntityPerSecond: 0
        });
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau;
        rcau.agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        rcau.deadline = uint64(block.timestamp + 1 hours);
        rcau.endsAt = uint64(block.timestamp + 365 days);
        rcau.maxInitialTokens = 0;
        rcau.maxOngoingTokensPerSecond = 1;
        rcau.minSecondsPerCollection = 1;
        rcau.maxSecondsPerCollection = 3600;
        rcau.conditions = 0;
        rcau.minSecondsPayerCancellationNotice = 0;
        rcau.nonce = 1;
        rcau.metadata = _encodeUpdateIndexingAgreementMetadataV1(
            _newUpdateIndexingAgreementMetadataV1(updateTerms.tokensPerSecond, updateTerms.tokensPerEntityPerSecond)
        );

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 hash = recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, hash, bytes(""), 0);

        // Collection after revival should produce tokens
        skip(100);
        resetPrank(indexer.addr);
        uint256 postRevivalCollect = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(postRevivalCollect > 0, "post-revival collection should succeed");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  14. Callback revert on accept
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When the data service callback reverts during accept, the collector state
    ///         stays in REGISTERED (the whole tx rolls back).
    function test_CallbackRevertOnAccept_CollectorStateUnchanged(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        // Offer an agreement
        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRCA(ctx, indexer.addr);

        resetPrank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Close the allocation so the SS acceptAgreement callback will revert
        resetPrank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        // Try to accept -- callback reverts, entire tx reverts
        bytes32 versionHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        resetPrank(indexer.addr);
        vm.expectRevert();
        recurringCollector.accept(agreementId, versionHash, abi.encode(indexer.allocationId), 0);

        // Collector state should remain REGISTERED (not ACCEPTED)
        IRecurringCollector.AgreementData memory data = recurringCollector.getAgreementData(agreementId);
        assertEq(data.state, REGISTERED, "should remain REGISTERED after failed accept");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  15. Notice period shorter than minSecondsPerCollection
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When cancellation notice (60s) < minSecondsPerCollection (3600s),
    ///         the provider cannot collect during the notice window but CAN collect
    ///         after collectableUntil because minSecondsPerCollection is waived.
    function test_NoticeShorterThanMinCollection_FinalCollectAfterExpiry(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);

        uint256 maxTokens = 100_000;
        _addTokensToProvision(indexer, maxTokens * STAKE_TO_FEES_RATIO);

        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _withControlledAgreement(
            ctx,
            indexer,
            uint64(block.timestamp + 365 days),
            3600, // minSecondsPerCollection = 1 hour (large)
            7200, // maxSecondsPerCollection = 2 hours
            60, // minSecondsPayerCancellationNotice = 1 minute (tiny)
            1, // 1 token/sec
            maxTokens
        );

        resetPrank(indexer.addr);
        subgraphService.setPaymentsDestination(indexer.addr);

        // First collection -- satisfies minSecondsPerCollection
        skip(3600);
        resetPrank(indexer.addr);
        _collectIndexingFees(indexer.addr, agreementId);

        // Payer cancels -- collectableUntil = now + 60
        uint256 cancelTimestamp = block.timestamp;
        resetPrank(rca.payer);
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        recurringCollector.cancel(agreementId, activeHash, 0);

        IRecurringCollector.AgreementData memory afterCancel = recurringCollector.getAgreementData(agreementId);
        assertEq(afterCancel.state & NOTICE_GIVEN, NOTICE_GIVEN, "should be NOTICE_GIVEN");
        uint64 expectedCollectableUntil = uint64(cancelTimestamp + 60);
        assertEq(afterCancel.collectableUntil, expectedCollectableUntil, "collectableUntil = now + notice");

        // After collectableUntil: minSecondsPerCollection is waived
        vm.warp(expectedCollectableUntil + 1);

        IRecurringCollector.AgreementData memory afterExpiry = recurringCollector.getAgreementData(agreementId);
        assertTrue(afterExpiry.isCollectable, "should be collectable after collectableUntil (minSec waived)");

        // Final collection succeeds
        resetPrank(indexer.addr);
        uint256 finalCollect = _collectIndexingFees(indexer.addr, agreementId);
        assertTrue(finalCollect > 0, "final collection after notice expiry should succeed");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
