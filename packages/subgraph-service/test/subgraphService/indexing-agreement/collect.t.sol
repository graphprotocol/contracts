// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

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
        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: accepted.rca.agreementId,
                collectionId: bytes32(uint256(uint160(indexerState.allocationId))),
                tokens: 0,
                dataServiceCut: 0
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
        emit ISubgraphService.IndexingFeesCollectedV1(
            indexerState.addr,
            accepted.rca.payer,
            accepted.rca.agreementId,
            indexerState.allocationId,
            indexerState.subgraphDeploymentId,
            epochManager.currentEpoch(),
            tokensCollected,
            entities,
            poi,
            epochManager.currentEpoch()
        );
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, epochManager.currentEpoch())
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
        uint256 currentEpoch = epochManager.currentEpoch();
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(indexer);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
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
        uint256 currentEpoch = epochManager.currentEpoch();
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
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
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
        uint256 currentEpoch = epochManager.currentEpoch();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

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
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
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
        uint256 currentEpoch = epochManager.currentEpoch();
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidAgreement(
        Seed memory seed,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
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

        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            accepted.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, currentEpoch)
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

        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            accepted.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            indexerState.addr,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(accepted.rca.agreementId, entities, poi, currentEpoch)
        );
    }
    /* solhint-enable graph/func-name-mixedcase */
}
