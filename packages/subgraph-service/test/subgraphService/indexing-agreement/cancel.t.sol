// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCancelTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenPaused(
        address rando,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(rando) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(rando);
        subgraphService.cancelIndexingAgreementByPayer(agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenNotAuthorized(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA,
        address rando
    ) public withSafeIndexerOrOperator(rando) {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNonCancelableBy.selector,
            signedRCA.rca.payer,
            rando
        );
        vm.expectRevert(expectedErr);
        resetPrank(rando);
        subgraphService.cancelIndexingAgreementByPayer(signedRCA.rca.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        bytes16 agreementId
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenCanceled(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA,
        bool cancelSource
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        _cancelAgreementBy(params.indexer, signedRCA.rca.payer, signedRCA.rca.agreementId, cancelSource);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            signedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(signedRCA.rca.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);

        _cancelAgreementByPayer(signedRCA.rca.payer, signedRCA.rca.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenPaused(
        address operator,
        address indexer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(operator);
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotAuthorized(
        address operator,
        address indexer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != indexer);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        bytes16 agreementId,
        uint256 unboundedTokens
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
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        bytes16 agreementId,
        uint256 unboundedTokens
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
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        bytes16 agreementId
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(params.indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenCanceled(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA,
        bool cancelSource
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        _cancelAgreementBy(params.indexer, signedRCA.rca.payer, signedRCA.rca.agreementId, cancelSource);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            signedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(params.indexer, signedRCA.rca.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA calldata fuzzySignedRCA
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);

        _cancelAgreementByIndexer(params.indexer, signedRCA.rca.agreementId);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
