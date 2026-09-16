// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { SCOPE_ACTIVE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementIntegrationTest is SubgraphServiceIndexingAgreementSharedTest {
    using PPMMath for uint256;

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
        bytes16 acceptedAgreementId = _sharedSetup(ctx, rca, indexerState, expectedTokens);

        // Cancel the indexing agreement by the payer
        resetPrank(ctx.payer.signer);
        subgraphService.cancelIndexingAgreementByPayer(acceptedAgreementId);

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

    /// @notice Payer-initiated scoped cancel via RC.cancel(id, hash, SCOPE_ACTIVE).
    /// Exercises the full reentrant callback chain:
    ///   payer → RC.cancel(id, hash, SCOPE_ACTIVE)
    ///     → SubgraphService.cancelIndexingAgreementByPayer(id)
    ///       → RC.cancel(id, CancelAgreementBy.Payer)
    /// Verifies the callback is not blocked by reentrancy and the agreement ends up canceled.
    function test_SubgraphService_ScopedCancelActive_ViaRecurringCollector_Integration(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Read activeTermsHash from the accepted agreement
        IRecurringCollector.AgreementData memory agreementData = recurringCollector.getAgreement(agreementId);
        bytes32 activeTermsHash = agreementData.activeTermsHash;
        assertTrue(activeTermsHash != bytes32(0), "activeTermsHash should be set after accept");

        // Expect the SubgraphService cancel event
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementCanceled(
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            agreementId,
            acceptedRca.payer
        );

        // Expect the RC cancel event from the callback
        vm.expectEmit(address(recurringCollector));
        emit IRecurringCollector.AgreementCanceled(
            acceptedRca.dataService,
            acceptedRca.payer,
            acceptedRca.serviceProvider,
            agreementId,
            IRecurringCollector.CancelAgreementBy.Payer
        );

        // Payer calls RC's scoped cancel — triggers the full callback chain.
        // Single-shot vm.prank (not resetPrank/startPrank) so the prank ends with this
        // call. Otherwise the post-cancel view-reads below would inherit the prank, and
        // when the fuzzer happens to pick the SubgraphService proxy's admin address as
        // rca.payer, the proxy would reject those reads with ProxyDeniedAdminAccess.
        vm.stopPrank();
        vm.prank(acceptedRca.payer);
        recurringCollector.cancel(agreementId, activeTermsHash, SCOPE_ACTIVE);

        // Verify agreement is canceled in RecurringCollector
        IRecurringCollector.AgreementData memory afterCancel = recurringCollector.getAgreement(agreementId);
        assertEq(
            uint8(afterCancel.state),
            uint8(IRecurringCollector.AgreementState.CanceledByPayer),
            "RC agreement should be CanceledByPayer"
        );
        assertEq(afterCancel.canceledAt, uint64(block.timestamp), "canceledAt should be set");

        // Verify agreement is canceled in SubgraphService
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            uint8(wrapper.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.CanceledByPayer),
            "SubgraphService should reflect CanceledByPayer"
        );
    }

    /// @notice Regression: rca.payer collides with SubgraphService's auto-deployed
    /// TransparentUpgradeableProxy admin (0x8816d8...). Without the post-cancel prank
    /// release, the verification reads from subgraphService inherit msg.sender = payer
    /// = proxyAdmin and revert with ProxyDeniedAdminAccess. Seed lifted from the
    /// failing fuzz counterexample on CI run 25387077283.
    function test_SubgraphService_ScopedCancelActive_PayerEqualsProxyAdmin_Regression() public {
        Seed memory seed;
        seed.indexer0 = IndexerSeed({
            addr: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38,
            label: "indexer0",
            unboundedProvisionTokens: 34685,
            unboundedAllocationPrivateKey: 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103,
            subgraphDeploymentId: bytes32(uint256(0x46dd))
        });
        seed.indexer1 = IndexerSeed({
            addr: address(uint160(0x2a59)),
            label: "indexer1",
            unboundedProvisionTokens: 10000,
            unboundedAllocationPrivateKey: 0x114a,
            subgraphDeploymentId: 0xd8d69c1da829f8277e4e80945a974b3ca009835eb268c14bf9321952f1cf169e
        });
        seed.rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: 11450,
            endsAt: 1000000000000000000,
            payer: 0x8816d87403E337Ff1349af38d49Ee0747079C55D,
            dataService: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38,
            serviceProvider: address(uint160(0x3e57)),
            maxInitialTokens: 3783,
            maxOngoingTokensPerSecond: 16028,
            minSecondsPerCollection: 208,
            maxSecondsPerCollection: 876,
            conditions: 1561,
            nonce: 0xb59b65b7215c7fb95ac34d2ad5aed7c775c8bc77ad936b1b43e17b95efc8e400,
            metadata: hex"0000000000000000000000000000000000000000000000000000000000000ad0"
        });
        seed.rcau = IRecurringCollector.RecurringCollectionAgreementUpdate({
            agreementId: bytes16(0),
            deadline: 962,
            endsAt: 19984,
            maxInitialTokens: 432000,
            maxOngoingTokensPerSecond: 1928028033,
            minSecondsPerCollection: 247,
            maxSecondsPerCollection: 766814522,
            conditions: 32,
            nonce: 2123,
            metadata: hex"676f7665726e6f72"
        });
        seed.termsV1 = IndexingAgreement.IndexingAgreementTermsV1({
            tokensPerSecond: 16465,
            tokensPerEntityPerSecond: 1
        });
        seed.payer = PayerSeed({ unboundedSignerPrivateKey: 10000 });

        test_SubgraphService_ScopedCancelActive_ViaRecurringCollector_Integration(seed);
    }

    function test_SubgraphService_CollectIndexingRewards_ResizesToZeroWhenOverAllocated_Integration(
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

        // Collect indexing rewards - resizes allocation to zero (not close+cancel)
        bytes memory collectData = abi.encode(indexerState.allocationId, keccak256("poi"), bytes("metadata"));
        resetPrank(indexerState.addr);
        subgraphService.collect(indexerState.addr, IGraphPayments.PaymentTypes.IndexingRewards, collectData);

        // Allocation resized to zero but stays open; agreement remains active
        IAllocation.State memory allocation = subgraphService.getAllocation(indexerState.allocationId);
        assertEq(allocation.closedAt, 0, "allocation should still be open");
        assertEq(allocation.tokens, 0, "allocation should be resized to zero");

        IIndexingAgreement.AgreementWrapper memory agreement = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            uint8(agreement.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "agreement should remain active"
        );
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _sharedSetup(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IndexerState memory _indexerState,
        ExpectedTokens memory _expectedTokens
    ) internal returns (bytes16) {
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

        _setupPayerWithEscrow(
            _rca.payer,
            _ctx.payer.signerPrivateKey,
            _indexerState.addr,
            _expectedTokens.expectedTotalTokensCollected
        );

        resetPrank(_indexerState.addr);
        // Set the payments destination to the indexer address
        subgraphService.setPaymentsDestination(_indexerState.addr);

        // Accept the Indexing Agreement
        (
            IRecurringCollector.RecurringCollectionAgreement memory signedRca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(_rca, _ctx.payer.signerPrivateKey);
        bytes16 agreementId = subgraphService.acceptIndexingAgreement(_indexerState.allocationId, signedRca, signature);

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

    function _setupPayerWithEscrow(
        address _payer,
        uint256 _signerPrivateKey,
        address _indexer,
        uint256 _escrowTokens
    ) private {
        _recurringCollectorHelper.authorizeSignerWithChecks(_payer, _signerPrivateKey);

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
