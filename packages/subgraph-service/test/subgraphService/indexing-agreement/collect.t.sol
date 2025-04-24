// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCollectTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFees(
        SetupTestIndexerParams calldata fuzzyParams,
        uint256 entities,
        bytes32 poi,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA,
        uint256 unboundedTokensCollected
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);

        assertEq(subgraphService.feesProvisionTracker(params.indexer), 0, "Should be 0 before collect");

        resetPrank(params.indexer);
        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: signedRCA.rca.agreementId,
                collectionId: bytes32(uint256(uint160(params.allocationId))),
                tokens: 0,
                dataServiceCut: 0
            })
        );
        uint256 tokensCollected = bound(unboundedTokensCollected, 1, params.tokens / stakeToFeesRatio);
        _mockCollectorCollect(address(recurringCollector), data, tokensCollected);
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingFeesCollectedV1(
            params.indexer,
            signedRCA.rca.payer,
            signedRCA.rca.agreementId,
            params.allocationId,
            params.subgraphDeploymentId,
            epochManager.currentEpoch(),
            tokensCollected,
            entities,
            poi,
            epochManager.currentEpoch()
        );
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(signedRCA.rca.agreementId, entities, poi, epochManager.currentEpoch())
        );

        assertEq(
            subgraphService.feesProvisionTracker(params.indexer),
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
        SetupTestIndexerParams calldata fuzzyParams,
        bytes16 agreementId,
        uint256 entities,
        bytes32 poi
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(agreementId, entities, poi, currentEpoch)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenStopService(
        SetupTestIndexerParams calldata fuzzyParams,
        uint256 entities,
        bytes32 poi,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        _acceptAgreement(params, fuzzySignedRCA);

        _mockCollectorCancel(address(recurringCollector), fuzzySignedRCA.rca.agreementId);
        resetPrank(params.indexer);
        subgraphService.stopService(params.indexer, abi.encode(params.allocationId));

        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            fuzzySignedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(fuzzySignedRCA.rca.agreementId, entities, poi, currentEpoch)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenCloseStaleAllocation(
        SetupTestIndexerParams calldata fuzzyParams,
        uint256 entities,
        bytes32 poi,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        _acceptAgreement(params, fuzzySignedRCA);

        _mockCollectorCancel(address(recurringCollector), fuzzySignedRCA.rca.agreementId);
        skip(maxPOIStaleness + 1);
        resetPrank(params.indexer);
        subgraphService.closeStaleAllocation(params.allocationId);

        uint256 currentEpoch = epochManager.currentEpoch();

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            fuzzySignedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            _encodeCollectDataV1(fuzzySignedRCA.rca.agreementId, entities, poi, currentEpoch)
        );
    }
    /* solhint-enable graph/func-name-mixedcase */
}
