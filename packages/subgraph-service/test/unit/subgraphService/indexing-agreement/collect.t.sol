// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { Allocation } from "../../../../contracts/libraries/Allocation.sol";
import { AllocationHandler } from "../../../../contracts/libraries/AllocationHandler.sol";
import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCollectTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFees_OK(
        Seed memory seed,
        uint256 entities,
        bytes32 poi,
        uint256 unboundedTokensCollected
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );

        assertEq(subgraphService.feesProvisionTracker(indexerState.addr), 0, "Should be 0 before collect");

        resetPrank(indexerState.addr);
        subgraphService.setPaymentsDestination(indexerState.addr);

        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: acceptedAgreementId,
                collectionId: bytes32(uint256(uint160(indexerState.allocationId))),
                tokens: 0,
                dataServiceCut: 0,
                receiverDestination: indexerState.addr,
                maxSlippage: type(uint256).max
            })
        );
        uint256 tokensCollected = bound(unboundedTokensCollected, 1, indexerState.tokens / STAKE_TO_FEES_RATIO);

        vm.mockCall(
            address(recurringCollector),
            abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, data),
            abi.encode(tokensCollected)
        );
        _expectCollectCallAndEmit(data, indexerState, accepted, acceptedAgreementId, tokensCollected, entities, poi);

        skip(1); // To make agreement collectable

        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(acceptedAgreementId, entities, poi, epochManager.currentEpochBlock(), bytes(""))
        );

        assertEq(
            subgraphService.feesProvisionTracker(indexerState.addr),
            tokensCollected * STAKE_TO_FEES_RATIO,
            "Should be exactly locked tokens"
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenPaused(
        address indexer,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(indexer);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenNotAuthorized(
        address operator,
        address indexer,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != indexer);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidProvision(
        uint256 unboundedTokens,
        address indexer,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            MINIMUM_PROVISION_TOKENS,
            MAXIMUM_PROVISION_TOKENS
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenIndexerNotRegistered(
        uint256 unboundedTokens,
        address indexer,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidData(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        bytes memory invalidData = bytes("invalid data");
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeCollectData",
            invalidData
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.collect(indexerState.addr, IGraphPayments.PaymentTypes.IndexingFee, invalidData);
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidAgreement(
        Seed memory seed,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();

        bytes memory expectedErr = abi.encodeWithSelector(IAllocation.AllocationDoesNotExist.selector, address(0));
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenInvalidNestedData(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        resetPrank(indexerState.addr);

        bytes memory invalidNestedData = bytes("invalid nested data");
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeCollectIndexingFeeDataV1",
            invalidNestedData
        );
        vm.expectRevert(expectedErr);

        skip(1); // To make agreement collectable

        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectData(acceptedAgreementId, invalidNestedData)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenIndexingAgreementNotAuthorized(
        Seed memory seed,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IndexerState memory otherIndexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        vm.assume(otherIndexerState.addr != indexerState.addr);

        resetPrank(otherIndexerState.addr);

        uint256 currentEpochBlock = epochManager.currentEpochBlock();

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotAuthorized.selector,
            acceptedAgreementId,
            otherIndexerState.addr
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            otherIndexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(acceptedAgreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenStopService(
        Seed memory seed,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        resetPrank(indexerState.addr);
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));

        uint256 currentEpochBlock = epochManager.currentEpochBlock();

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationHandler.AllocationHandlerAllocationClosed.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(acceptedAgreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenCloseStaleAllocation(
        Seed memory seed,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerState);

        skip(MAX_POI_STALENESS + 1);
        resetPrank(indexerState.addr);
        subgraphService.closeStaleAllocation(indexerState.allocationId);

        uint256 currentEpochBlock = epochManager.currentEpochBlock();

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationHandler.AllocationHandlerAllocationClosed.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(acceptedAgreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _expectCollectCallAndEmit(
        bytes memory _data,
        IndexerState memory _indexerState,
        IRecurringCollector.SignedRCA memory _accepted,
        bytes16 _acceptedAgreementId,
        uint256 _tokensCollected,
        uint256 _entities,
        bytes32 _poi
    ) private {
        vm.expectCall(
            address(recurringCollector),
            abi.encodeCall(IPaymentsCollector.collect, (IGraphPayments.PaymentTypes.IndexingFee, _data))
        );
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingFeesCollectedV1(
            _indexerState.addr,
            _accepted.rca.payer,
            _acceptedAgreementId,
            _indexerState.allocationId,
            _indexerState.subgraphDeploymentId,
            epochManager.currentEpoch(),
            _tokensCollected,
            _entities,
            _poi,
            epochManager.currentEpochBlock(),
            bytes("")
        );
    }
}
