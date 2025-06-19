// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
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
        _sharedSetup(ctx, rca, indexerState, expectedTokens);

        TestState memory beforeCollect = _getState(rca.payer, indexerState.addr);

        // Collect
        resetPrank(indexerState.addr);
        uint256 tokensCollected = subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                rca.agreementId,
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
        _sharedSetup(ctx, rca, indexerState, expectedTokens);

        // Cancel the indexing agreement by the payer
        resetPrank(ctx.payer.signer);
        subgraphService.cancelIndexingAgreementByPayer(rca.agreementId);

        TestState memory beforeCollect = _getState(rca.payer, indexerState.addr);

        // Collect
        resetPrank(indexerState.addr);
        uint256 tokensCollected = subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                rca.agreementId,
                1,
                keccak256(abi.encodePacked("poi")),
                epochManager.currentEpochBlock(),
                bytes("")
            )
        );

        TestState memory afterCollect = _getState(rca.payer, indexerState.addr);
        _sharedAssert(beforeCollect, afterCollect, expectedTokens, tokensCollected);
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _sharedSetup(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IndexerState memory _indexerState,
        ExpectedTokens memory _expectedTokens
    ) internal {
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
        subgraphService.acceptIndexingAgreement(
            _indexerState.allocationId,
            _recurringCollectorHelper.generateSignedRCA(_rca, _ctx.payer.signerPrivateKey)
        );

        // Skip ahead to collection point
        skip(_expectedTokens.expectedTotalTokensCollected / terms.tokensPerSecond);
    }

    function _newExpectedTokens(uint256 _fuzzyTokensCollected) internal view returns (ExpectedTokens memory) {
        uint256 expectedTotalTokensCollected = bound(_fuzzyTokensCollected, 1000, 1_000_000);
        uint256 expectedTokensLocked = stakeToFeesRatio * expectedTotalTokensCollected;
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

    function _addTokensToProvision(IndexerState memory _indexerState, uint256 _tokensToAddToProvision) private {
        deal({ token: address(token), to: _indexerState.addr, give: _tokensToAddToProvision });
        vm.startPrank(_indexerState.addr);
        _addToProvision(_indexerState.addr, _tokensToAddToProvision);
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

        return
            TestState({
                escrowBalance: escrow.getBalance(_payer, address(recurringCollector), _indexer),
                indexerBalance: collect.indexerBalance,
                indexerTokensLocked: collect.lockedTokens
            });
    }
}
