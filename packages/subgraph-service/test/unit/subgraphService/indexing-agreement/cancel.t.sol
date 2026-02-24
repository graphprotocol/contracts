// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";

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
        Seed memory seed,
        address rando
    ) public withSafeIndexerOrOperator(rando) {
        Context storage ctx = _newCtx(seed);
        vm.assume(rando != seed.rca.payer);
        vm.assume(rando != ctx.payer.signer);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 agreementId) = _withAcceptedIndexingAgreement(
            ctx,
            _withIndexer(ctx)
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNonCancelableBy.selector,
            accepted.rca.payer,
            rando
        );
        vm.expectRevert(expectedErr);
        resetPrank(rando);
        subgraphService.cancelIndexingAgreementByPayer(agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenNotAccepted(
        Seed memory seed,
        bytes16 agreementId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        resetPrank(indexerState.addr);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenCanceled(
        Seed memory seed,
        bool cancelSource
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.CancelAgreementBy by = cancelSource
            ? IRecurringCollector.CancelAgreementBy.ServiceProvider
            : IRecurringCollector.CancelAgreementBy.Payer;
        _cancelAgreement(ctx, acceptedAgreementId, indexerState.addr, accepted.rca.payer, by);

        resetPrank(indexerState.addr);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptedAgreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(acceptedAgreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(
            ctx,
            _withIndexer(ctx)
        );

        _cancelAgreement(
            ctx,
            acceptedAgreementId,
            accepted.rca.serviceProvider,
            accepted.rca.payer,
            IRecurringCollector.CancelAgreementBy.Payer
        );
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
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
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
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        bytes16 agreementId,
        uint256 unboundedTokens
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotAccepted(
        Seed memory seed,
        bytes16 agreementId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        resetPrank(indexerState.addr);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexerState.addr, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenCanceled(
        Seed memory seed,
        bool cancelSource
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.CancelAgreementBy by = cancelSource
            ? IRecurringCollector.CancelAgreementBy.ServiceProvider
            : IRecurringCollector.CancelAgreementBy.Payer;
        _cancelAgreement(ctx, acceptedAgreementId, accepted.rca.serviceProvider, accepted.rca.payer, by);

        resetPrank(indexerState.addr);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptedAgreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexerState.addr, acceptedAgreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(
            ctx,
            _withIndexer(ctx)
        );

        _cancelAgreement(
            ctx,
            acceptedAgreementId,
            accepted.rca.serviceProvider,
            accepted.rca.payer,
            IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }
    /* solhint-enable graph/func-name-mixedcase */
}
