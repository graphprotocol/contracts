// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementAcceptTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenPaused(
        address allocationId,
        address operator,
        IRecurringCollector.SignedRCA calldata signedRCA
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotAuthorized(
        address allocationId,
        address operator,
        IRecurringCollector.SignedRCA calldata signedRCA
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != signedRCA.rca.serviceProvider);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            signedRCA.rca.serviceProvider,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

        signedRCA.rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);
        signedRCA.rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotDataService(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        vm.assume(signedRCA.rca.dataService != address(subgraphService));
        signedRCA.rca.serviceProvider = params.indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementWrongDataService.selector,
            signedRCA.rca.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidMetadata(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCA.rca.serviceProvider = params.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = bytes("invalid");
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceDecoderInvalidData.selector,
            "_decodeRCAMetadata",
            signedRCA.rca.metadata
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidAllocation(
        SetupTestIndexerParams calldata fuzzyParams,
        address invalidAllocationId,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCA.rca.serviceProvider = params.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = abi.encode(_createRCAMetadataV1(params.subgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            Allocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(invalidAllocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationNotAuthorized(
        SetupTestIndexerParams calldata fuzzyParamsA,
        SetupTestIndexerParams calldata fuzzyParamsB,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        vm.assume(fuzzyParamsA.indexer != fuzzyParamsB.indexer);
        vm.assume(fuzzyParamsA.unboundedAllocationPrivateKey != fuzzyParamsB.unboundedAllocationPrivateKey);
        TestIndexerParams memory paramsA = _setupTestIndexer(fuzzyParamsA);
        TestIndexerParams memory paramsB = _setupTestIndexer(fuzzyParamsB);
        signedRCA.rca.serviceProvider = paramsA.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = abi.encode(_createRCAMetadataV1(paramsA.subgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            paramsA.indexer,
            paramsB.allocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(paramsA.indexer);
        subgraphService.acceptIndexingAgreement(paramsB.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationClosed(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCA.rca.serviceProvider = params.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = abi.encode(_createRCAMetadataV1(params.subgraphDeploymentId));

        resetPrank(params.indexer);
        subgraphService.stopService(params.indexer, abi.encode(params.allocationId));
        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationClosed.selector,
            params.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenDeploymentIdMismatch(
        SetupTestIndexerParams calldata fuzzyParams,
        bytes32 wrongSubgraphDeploymentId,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        vm.assume(fuzzyParams.subgraphDeploymentId != wrongSubgraphDeploymentId);
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCA.rca.serviceProvider = params.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = abi.encode(_createRCAMetadataV1(wrongSubgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementDeploymentIdMismatch.selector,
            wrongSubgraphDeploymentId,
            params.allocationId,
            params.subgraphDeploymentId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        vm.assume(signedRCA.rca.agreementId != bytes16(0));
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCA.rca.serviceProvider = params.indexer;
        signedRCA.rca.dataService = address(subgraphService);
        signedRCA.rca.metadata = abi.encode(_createRCAMetadataV1(params.subgraphDeploymentId));

        _mockCollectorAccept(address(recurringCollector), signedRCA);

        resetPrank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementAlreadyAccepted.selector,
            signedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAllocated() public {}

    function test_SubgraphService_AcceptIndexingAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory signedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        _acceptAgreement(params, signedRCA);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
