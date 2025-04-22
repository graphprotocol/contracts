// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

import { RecurringCollectorHelper } from "@graphprotocol/horizon/test/payments/recurring-collector/RecurringCollectorHelper.t.sol";

contract SubgraphServiceIndexingAgreementCancelTest is SubgraphServiceIndexingAgreementSharedTest {
    using PPMMath for uint256;

    struct TestState {
        uint256 escrowBalance;
        uint256 indexerBalance;
        uint256 indexerTokensLocked;
    }

    RecurringCollectorHelper private _recurringCollectorHelper;

    function setUp() public override {
        super.setUp();

        _recurringCollectorHelper = new RecurringCollectorHelper(recurringCollector);
    }

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFee_Integration(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA,
        uint256 unboundedSignerPrivateKey,
        uint256 fuzzyTokensCollected
    ) public {
        uint256 expectedTotalTokensCollected = bound(fuzzyTokensCollected, 1000, 1_000_000);
        uint256 expectedTokensLocked = stakeToFeesRatio * expectedTotalTokensCollected;
        uint256 expectedProtocolTokensBurnt = expectedTotalTokensCollected.mulPPMRoundUp(
            graphPayments.PROTOCOL_PAYMENT_CUT()
        );
        uint256 expectedIndexerTokensCollected = expectedTotalTokensCollected - expectedProtocolTokensBurnt;
        TestIndexerParams memory params = _setupIndexer(fuzzyParams, expectedTokensLocked);
        uint256 signerPrivateKey = boundKey(unboundedSignerPrivateKey);
        vm.assume(fuzzyRCA.payer != address(0));
        _setupPayerWithEscrow(fuzzyRCA.payer, signerPrivateKey, params.indexer, expectedTotalTokensCollected);
        uint256 agreementTokensPerSecond = 1;
        // Create the Indexing Agreement
        fuzzyRCA.deadline = block.timestamp; // accept now
        fuzzyRCA.duration = type(uint256).max; // no expiration
        fuzzyRCA.maxInitialTokens = 0; // no initial payment
        fuzzyRCA.maxOngoingTokensPerSecond = type(uint32).max; // unlimited tokens per second
        fuzzyRCA.minSecondsPerCollection = 1; // 1 second between collections
        fuzzyRCA.maxSecondsPerCollection = type(uint32).max; // no maximum time between collections
        fuzzyRCA.serviceProvider = params.indexer; // service provider is the indexer
        fuzzyRCA.dataService = address(subgraphService); // data service is the subgraph service
        fuzzyRCA.metadata = _encodeRCAMetadataV1(
            params.subgraphDeploymentId,
            ISubgraphService.IndexingAgreementTermsV1({
                tokensPerSecond: agreementTokensPerSecond,
                tokensPerEntityPerSecond: 0 // no payment for entities
            })
        );
        resetPrank(params.indexer);
        // Accept the Indexing Agreement
        subgraphService.acceptIndexingAgreement(
            params.allocationId,
            _recurringCollectorHelper.generateSignedRCA(fuzzyRCA, signerPrivateKey)
        );
        // Skip ahead to collection point
        skip(expectedTotalTokensCollected / agreementTokensPerSecond);
        TestState memory beforeCollect = _getState(fuzzyRCA.payer, params.indexer);
        bytes16 agreementId = fuzzyRCA.agreementId;
        uint256 tokensCollected = subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, 1, keccak256(abi.encodePacked("poi")), epochManager.currentEpoch())
        );
        TestState memory afterCollect = _getState(fuzzyRCA.payer, params.indexer);
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

    function _setupIndexer(
        SetupTestIndexerParams calldata _fuzzyParams,
        uint256 _tokensToAddToProvision
    ) private returns (TestIndexerParams memory) {
        TestIndexerParams memory params = _setupTestIndexer(_fuzzyParams);
        deal({ token: address(token), to: params.indexer, give: _tokensToAddToProvision });
        vm.startPrank(params.indexer);
        _addToProvision(params.indexer, _tokensToAddToProvision);
        vm.stopPrank();

        return params;
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
