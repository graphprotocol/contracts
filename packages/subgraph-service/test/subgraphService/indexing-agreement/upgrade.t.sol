// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementUpgradeTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_UpgradeIndexingAgreementIndexingAgreement_Revert_WhenPaused(
        address operator,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.upgradeIndexingAgreement(operator, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenNotAuthorized(
        address indexer,
        address notAuthorized,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) public withSafeIndexerOrOperator(notAuthorized) {
        vm.assume(notAuthorized != indexer);
        resetPrank(notAuthorized);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            notAuthorized
        );
        vm.expectRevert(expectedErr);
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
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
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            signedRCAU.rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.upgradeIndexingAgreement(params.indexer, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenNotAuthorizedForAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        SetupTestIndexerParams calldata fuzzyOtherParams,
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        IRecurringCollector.SignedRCAU memory fuzzySignedRCAU
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        TestIndexerParams memory otherParams = _setupTestIndexer(fuzzyOtherParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        fuzzySignedRCAU.rcau.agreementId = signedRCA.rca.agreementId;

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotAuthorized.selector,
            fuzzySignedRCAU.rcau.agreementId,
            otherParams.indexer
        );
        vm.expectRevert(expectedErr);
        resetPrank(otherParams.indexer);
        subgraphService.upgradeIndexingAgreement(otherParams.indexer, fuzzySignedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenInvalidMetadata(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        IRecurringCollector.SignedRCAU memory fuzzySignedRCAU
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        fuzzySignedRCAU.rcau.agreementId = signedRCA.rca.agreementId;
        fuzzySignedRCAU.rcau.metadata = bytes("invalid");

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceDecoderInvalidData.selector,
            "_decodeRCAUMetadata",
            fuzzySignedRCAU.rcau.metadata
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.upgradeIndexingAgreement(params.indexer, fuzzySignedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_OK(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        IRecurringCollector.SignedRCAU memory fuzzySignedRCAU,
        uint256 tokensPerSecond,
        uint256 tokensPerEntityPerSecond
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        fuzzySignedRCAU.rcau.agreementId = signedRCA.rca.agreementId;
        fuzzySignedRCAU.rcau.metadata = _encodeRCAUMetadataV1(
            _createRCAUMetadataV1(tokensPerSecond, tokensPerEntityPerSecond)
        );
        _mockCollectorUpgrade(address(recurringCollector), fuzzySignedRCAU);
        resetPrank(params.indexer);
        subgraphService.upgradeIndexingAgreement(params.indexer, fuzzySignedRCAU);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
