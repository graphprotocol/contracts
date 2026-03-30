// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { Allocation } from "../../../../contracts/libraries/Allocation.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementIntegrationTest is SubgraphServiceIndexingAgreementSharedTest {
    using PPMMath for uint256;
    using Allocation for IAllocation.State;

    struct TestState {
        uint256 escrowBalance;
        uint256 indexerBalance;
        uint256 indexerTokensLocked;
    }

    struct ExpectedTokens {
        uint256 expectedTotalTokensCollected;
        uint256 expectedTokensLocked;
        uint256 expectedProtocolTokensBurnt;
        uint256 expectedIndexerTokensCollected;
    }

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFee_Integration(
        Seed memory seed,
        uint256 fuzzyTokensCollected
    ) public {
        // Setup
        ExpectedTokens memory expectedTokens = _newExpectedTokens(fuzzyTokensCollected);
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        _addTokensToProvision(indexerState, expectedTokens.expectedTokensLocked);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            ctx.ctxInternal.seed.rca
        );
        bytes16 acceptedAgreementId = _sharedSetup(ctx, rca, indexerState, expectedTokens);

        TestState memory beforeCollect = _getState(rca.payer, indexerState.addr);

        // Collect
        resetPrank(indexerState.addr);
        uint256 tokensCollected = subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                acceptedAgreementId,
                1,
                keccak256(abi.encodePacked("poi")),
                epochManager.currentEpochBlock(),
                bytes("")
            )
        );

        TestState memory afterCollect = _getState(rca.payer, indexerState.addr);
        _sharedAssert(beforeCollect, afterCollect, expectedTokens, tokensCollected);
    }

    function test_SubgraphService_CollectIndexingFee_WhenCanceledByPayer_Integration(
        Seed memory seed,
        uint256 fuzzyTokensCollected
    ) public {
        // Setup
        ExpectedTokens memory expectedTokens = _newExpectedTokens(fuzzyTokensCollected);
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            ctx.ctxInternal.seed.rca
        );
        // Payer must differ from indexer, otherwise cancel resolves as BY_PROVIDER (forfeit → settled)
        vm.assume(rca.payer != indexerState.addr);
        bytes16 acceptedAgreementId = _sharedSetup(ctx, rca, indexerState, expectedTokens);

        // Collect the funded tokens first
        resetPrank(indexerState.addr);
        TestState memory beforeCollect = _getState(rca.payer, indexerState.addr);

        uint256 tokensCollected = subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                acceptedAgreementId,
                1,
                keccak256(abi.encodePacked("poi")),
                epochManager.currentEpochBlock(),
                bytes("")
            )
        );

        TestState memory afterCollect = _getState(rca.payer, indexerState.addr);
        _sharedAssert(beforeCollect, afterCollect, expectedTokens, tokensCollected);

        // Cancel the indexing agreement by the payer (directly on collector).
        // Payer cancel enforces minSecondsPayerCancellationNotice — agreement enters
        // NOTICE_GIVEN | BY_PAYER state with collectableUntil in the future.
        resetPrank(rca.payer);
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(acceptedAgreementId, 0).versionHash;
        recurringCollector.cancel(acceptedAgreementId, activeHash, 0);

        // Verify agreement is in NOTICE_GIVEN state
        IRecurringCollector.AgreementData memory agreement = recurringCollector.getAgreementData(acceptedAgreementId);
        assertTrue(agreement.state & NOTICE_GIVEN != 0, "should be in NOTICE_GIVEN state after payer cancel");
    }

    function test_SubgraphService_CollectIndexingRewards_ResizesAllocationWhenOverAllocated_Integration(
        Seed memory seed
    ) public {
        // Setup context and indexer with active agreement
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Ensure enough gap so that reward distribution (1% of tokens) doesn't undo the over-allocation
        vm.assume(indexerState.tokens > MINIMUM_PROVISION_TOKENS * 2);

        // Reduce indexer's provision to force over-allocation after collecting rewards
        uint256 extraTokens = indexerState.tokens - MINIMUM_PROVISION_TOKENS;
        _removeTokensFromProvision(indexerState, extraTokens);

        // Verify indexer will be over-allocated after presenting POI
        assertTrue(subgraphService.isOverAllocated(indexerState.addr));

        // Advance past allocation creation epoch so POI is not considered "too young"
        vm.roll(block.number + EPOCH_LENGTH);

        // Collect indexing rewards - this should trigger allocation downsize (not closure)
        bytes memory collectData = abi.encode(indexerState.allocationId, keccak256("poi"), bytes("metadata"));
        resetPrank(indexerState.addr);

        subgraphService.collect(indexerState.addr, IGraphPayments.PaymentTypes.IndexingRewards, collectData);

        // Verify the allocation is still open but resized to zero
        IAllocation.State memory allocation = subgraphService.getAllocation(indexerState.allocationId);
        assertTrue(allocation.isOpen());
        assertEq(allocation.tokens, 0);

        // Verify the indexing agreement was NOT cancelled — it stays active
        IIndexingAgreement.AgreementWrapper memory agreement = subgraphService.getIndexingAgreement(agreementId);
        assertEq(agreement.collectorAgreement.state, REGISTERED | ACCEPTED);
    }

    function test_SubgraphService_StopService_RevertsWhenGuardEnabledAndActiveAgreement_Integration(
        Seed memory seed
    ) public {
        // Setup context and indexer with active agreement
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Enable the close allocation guard
        resetPrank(users.governor);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);

        // Attempt to close the allocation — should revert because of active agreement
        resetPrank(indexerState.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationHasActiveAgreement.selector,
                indexerState.allocationId,
                agreementId
            )
        );
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _sharedSetup(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IndexerState memory _indexerState,
        ExpectedTokens memory _expectedTokens
    ) internal returns (bytes16) {
        // Exclude payer addresses that collide with protocol contracts to prevent
        // token routing issues (e.g., receiverDestination == escrow)
        vm.assume(!_isProtocolContract(_rca.payer));
        vm.assume(!_isTestUser(_rca.payer));
        _addTokensToProvision(_indexerState, _expectedTokens.expectedTokensLocked);

        IndexingAgreement.IndexingAgreementTermsV1 memory terms = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 1,
            tokensPerEntityPerSecond: 0 // no payment for entities
        });
        _rca.deadline = uint64(block.timestamp); // accept now
        _rca.endsAt = type(uint64).max; // no expiration
        _rca.maxInitialTokens = 0; // no initial payment
        _rca.maxOngoingTokensPerSecond = type(uint32).max; // unlimited tokens per second
        _rca.minSecondsPerCollection = 1; // 1 second between collections
        _rca.maxSecondsPerCollection = type(uint32).max; // no maximum time between collections
        _rca.serviceProvider = _indexerState.addr; // service provider is the indexer
        _rca.dataService = address(subgraphService); // data service is the subgraph service
        _rca.metadata = _encodeAcceptIndexingAgreementMetadataV1(_indexerState.subgraphDeploymentId, terms);

        _setupPayerWithEscrow(_rca.payer, _indexerState.addr, _expectedTokens.expectedTotalTokensCollected);

        resetPrank(_indexerState.addr);
        // Set the payments destination to the indexer address
        subgraphService.setPaymentsDestination(_indexerState.addr);
        vm.stopPrank();

        // Accept the Indexing Agreement via RC offer->accept flow
        // Step 1: Submit offer to RC
        vm.prank(_rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(_rca), 0).agreementId;

        // Step 2: Service provider accepts via RC, which callbacks to SS
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(_indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(_indexerState.allocationId), 0);

        // Skip ahead to collection point
        skip(_expectedTokens.expectedTotalTokensCollected / terms.tokensPerSecond);

        return agreementId;
    }

    function _newExpectedTokens(uint256 _fuzzyTokensCollected) internal view returns (ExpectedTokens memory) {
        uint256 expectedTotalTokensCollected = bound(_fuzzyTokensCollected, 1000, 1_000_000);
        uint256 expectedTokensLocked = STAKE_TO_FEES_RATIO * expectedTotalTokensCollected;
        uint256 expectedProtocolTokensBurnt = expectedTotalTokensCollected.mulPPMRoundUp(
            graphPayments.PROTOCOL_PAYMENT_CUT()
        );
        uint256 expectedIndexerTokensCollected = expectedTotalTokensCollected - expectedProtocolTokensBurnt;
        return
            ExpectedTokens({
                expectedTotalTokensCollected: expectedTotalTokensCollected,
                expectedTokensLocked: expectedTokensLocked,
                expectedProtocolTokensBurnt: expectedProtocolTokensBurnt,
                expectedIndexerTokensCollected: expectedIndexerTokensCollected
            });
    }

    function _sharedAssert(
        TestState memory _beforeCollect,
        TestState memory _afterCollect,
        ExpectedTokens memory _expectedTokens,
        uint256 _tokensCollected
    ) internal pure {
        uint256 indexerTokensCollected = _afterCollect.indexerBalance - _beforeCollect.indexerBalance;
        assertEq(_expectedTokens.expectedTotalTokensCollected, _tokensCollected, "Total tokens collected should match");
        assertEq(
            _expectedTokens.expectedProtocolTokensBurnt,
            _tokensCollected - indexerTokensCollected,
            "Protocol tokens burnt should match"
        );
        assertEq(
            _expectedTokens.expectedIndexerTokensCollected,
            indexerTokensCollected,
            "Indexer tokens collected should match"
        );
        assertEq(
            _afterCollect.escrowBalance,
            _beforeCollect.escrowBalance - _expectedTokens.expectedTotalTokensCollected,
            "_Escrow balance should be reduced by the amount collected"
        );

        assertEq(
            _afterCollect.indexerTokensLocked,
            _beforeCollect.indexerTokensLocked + _expectedTokens.expectedTokensLocked,
            "_Locked tokens should match"
        );
    }

    function _addTokensToProvision(IndexerState memory _indexerState, uint256 _tokens) private {
        deal({ token: address(token), to: _indexerState.addr, give: _tokens });
        vm.startPrank(_indexerState.addr);
        _addToProvision(_indexerState.addr, _tokens);
        vm.stopPrank();
    }

    function _removeTokensFromProvision(IndexerState memory _indexerState, uint256 _tokens) private {
        deal({ token: address(token), to: _indexerState.addr, give: _tokens });
        vm.startPrank(_indexerState.addr);
        _removeFromProvision(_indexerState.addr, _tokens);
        vm.stopPrank();
    }

    function _setupPayerWithEscrow(address _payer, address _indexer, uint256 _escrowTokens) private {
        deal({ token: address(token), to: _payer, give: _escrowTokens });
        vm.startPrank(_payer);
        _escrow(_escrowTokens, _indexer);
        vm.stopPrank();
    }

    function _escrow(uint256 _tokens, address _indexer) private {
        token.approve(address(escrow), _tokens);
        escrow.deposit(address(recurringCollector), _indexer, _tokens);
    }

    function _getState(address _payer, address _indexer) private view returns (TestState memory) {
        CollectPaymentData memory collect = _collectPaymentData(_indexer);
        (uint256 escrowBal, uint256 escrowThawing, ) = escrow.escrowAccounts(
            _payer,
            address(recurringCollector),
            _indexer
        );

        return
            TestState({
                escrowBalance: escrowBal - escrowThawing,
                indexerBalance: collect.indexerBalance,
                indexerTokensLocked: collect.lockedTokens
            });
    }
}
