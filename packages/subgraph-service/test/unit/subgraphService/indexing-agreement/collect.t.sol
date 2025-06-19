// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../../contracts/interfaces/ISubgraphService.sol";
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
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);

        assertEq(subgraphService.feesProvisionTracker(indexerState.addr), 0, "Should be 0 before collect");

        resetPrank(indexerState.addr);
        subgraphService.setPaymentsDestination(indexerState.addr);

        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: accepted.rca.agreementId,
                collectionId: bytes32(uint256(uint160(indexerState.allocationId))),
                tokens: 0,
                dataServiceCut: 0,
                receiverDestination: indexerState.addr
            })
        );
        uint256 tokensCollected = bound(unboundedTokensCollected, 1, indexerState.tokens / stakeToFeesRatio);
        vm.mockCall(
            address(recurringCollector),
            abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, data),
            abi.encode(tokensCollected)
        );
        vm.expectCall(
            address(recurringCollector),
            abi.encodeCall(IPaymentsCollector.collect, (IGraphPayments.PaymentTypes.IndexingFee, data))
        );
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingFeesCollectedV1(
            indexerState.addr,
            accepted.rca.payer,
            accepted.rca.agreementId,
            indexerState.allocationId,
            indexerState.subgraphDeploymentId,
            epochManager.currentEpoch(),
            tokensCollected,
            entities,
            poi,
            epochManager.currentEpochBlock(),
            bytes("")
        );
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, epochManager.currentEpochBlock(), bytes(""))
        );

        assertEq(
            subgraphService.feesProvisionTracker(indexerState.addr),
            tokensCollected * stakeToFeesRatio,
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
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, fishermanRewardPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
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
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        uint256 currentEpochBlock = epochManager.currentEpochBlock();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, fishermanRewardPercentage, disputePeriod);
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

        bytes memory expectedErr = abi.encodeWithSelector(Allocation.AllocationDoesNotExist.selector, address(0));
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
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);

        resetPrank(indexerState.addr);

        bytes memory invalidNestedData = bytes("invalid nested data");
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeCollectIndexingFeeDataV1",
            invalidNestedData
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectData(accepted.rca.agreementId, invalidNestedData)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenStopService(
        Seed memory seed,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);

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
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenCloseStaleAllocation(
        Seed memory seed,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);

        skip(maxPOIStaleness + 1);
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
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, currentEpochBlock, bytes(""))
        );
    }
    /* solhint-enable graph/func-name-mixedcase */
}
