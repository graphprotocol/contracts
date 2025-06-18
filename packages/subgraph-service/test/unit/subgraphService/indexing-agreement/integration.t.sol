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

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFee_Integration(
        Seed memory seed,
        uint256 fuzzyTokensCollected
    ) public {
        uint256 expectedTotalTokensCollected = bound(fuzzyTokensCollected, 1000, 1_000_000);
        uint256 expectedTokensLocked = stakeToFeesRatio * expectedTotalTokensCollected;
        uint256 expectedProtocolTokensBurnt = expectedTotalTokensCollected.mulPPMRoundUp(
            graphPayments.PROTOCOL_PAYMENT_CUT()
        );
        uint256 expectedIndexerTokensCollected = expectedTotalTokensCollected - expectedProtocolTokensBurnt;

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        _addTokensToProvision(indexerState, expectedTokensLocked);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            ctx.ctxInternal.seed.rca
        );
        uint256 agreementTokensPerSecond = 1;
        rca.deadline = uint64(block.timestamp); // accept now
        rca.endsAt = type(uint64).max; // no expiration
        rca.maxInitialTokens = 0; // no initial payment
        rca.maxOngoingTokensPerSecond = type(uint32).max; // unlimited tokens per second
        rca.minSecondsPerCollection = 1; // 1 second between collections
        rca.maxSecondsPerCollection = type(uint32).max; // no maximum time between collections
        rca.serviceProvider = indexerState.addr; // service provider is the indexer
        rca.dataService = address(subgraphService); // data service is the subgraph service
        rca.metadata = _encodeAcceptIndexingAgreementMetadataV1(
            indexerState.subgraphDeploymentId,
            IndexingAgreement.IndexingAgreementTermsV1({
                tokensPerSecond: agreementTokensPerSecond,
                tokensPerEntityPerSecond: 0 // no payment for entities
            })
        );

        _setupPayerWithEscrow(rca.payer, ctx.payer.signerPrivateKey, indexerState.addr, expectedTotalTokensCollected);

        resetPrank(indexerState.addr);
        // Set the payments destination to the indexer address
        subgraphService.setPaymentsDestination(indexerState.addr);
        // Accept the Indexing Agreement
        subgraphService.acceptIndexingAgreement(
            indexerState.allocationId,
            _recurringCollectorHelper.generateSignedRCA(rca, ctx.payer.signerPrivateKey)
        );
        // Skip ahead to collection point
        skip(expectedTotalTokensCollected / agreementTokensPerSecond);
        // vm.assume(block.timestamp < type(uint64).max);
        TestState memory beforeCollect = _getState(rca.payer, indexerState.addr);
        bytes16 agreementId = rca.agreementId;
        uint256 tokensCollected = subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(
                agreementId,
                1,
                keccak256(abi.encodePacked("poi")),
                epochManager.currentEpochBlock(),
                bytes("")
            )
        );
        TestState memory afterCollect = _getState(rca.payer, indexerState.addr);
        uint256 indexerTokensCollected = afterCollect.indexerBalance - beforeCollect.indexerBalance;
        uint256 protocolTokensBurnt = tokensCollected - indexerTokensCollected;
        assertEq(
            afterCollect.escrowBalance,
            beforeCollect.escrowBalance - tokensCollected,
            "Escrow balance should be reduced by the amount collected"
        );
        assertEq(tokensCollected, expectedTotalTokensCollected, "Total tokens collected should match");
        assertEq(expectedProtocolTokensBurnt, protocolTokensBurnt, "Protocol tokens burnt should match");
        assertEq(indexerTokensCollected, expectedIndexerTokensCollected, "Indexer tokens collected should match");
        assertEq(
            afterCollect.indexerTokensLocked,
            beforeCollect.indexerTokensLocked + expectedTokensLocked,
            "Locked tokens should match"
        );
    }

    /* solhint-enable graph/func-name-mixedcase */

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
