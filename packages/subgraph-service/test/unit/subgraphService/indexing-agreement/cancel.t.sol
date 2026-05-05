// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, _withIndexer(ctx));

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNonCancelableBy.selector,
            acceptedRca.payer,
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
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.CancelAgreementBy by = cancelSource
            ? IRecurringCollector.CancelAgreementBy.ServiceProvider
            : IRecurringCollector.CancelAgreementBy.Payer;
        _cancelAgreement(ctx, acceptedAgreementId, indexerState.addr, acceptedRca.payer, by);

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
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, _withIndexer(ctx));

        _cancelAgreement(
            ctx,
            acceptedAgreementId,
            acceptedRca.serviceProvider,
            acceptedRca.payer,
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

    // cancelIndexingAgreement uses enforceService(DEFAULT) — only authorization + pause.
    // No VALID_PROVISION or REGISTERED check. Cancel is an exit path.
    // With an invalid provision and no agreement, reverts with IndexingAgreementNotActive.
    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotActive_WithInvalidProvision(
        address indexer,
        bytes16 agreementId,
        uint256 unboundedTokens
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexer, agreementId);
    }

    // With valid provision but no registration or agreement, also reverts with IndexingAgreementNotActive.
    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotActive_WithoutRegistration(
        address indexer,
        bytes16 agreementId,
        uint256 unboundedTokens
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            agreementId
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
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca2,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.CancelAgreementBy by = cancelSource
            ? IRecurringCollector.CancelAgreementBy.ServiceProvider
            : IRecurringCollector.CancelAgreementBy.Payer;
        _cancelAgreement(ctx, acceptedAgreementId, acceptedRca2.serviceProvider, acceptedRca2.payer, by);

        resetPrank(indexerState.addr);
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptedAgreementId
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexerState.addr, acceptedAgreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenWrongIndexer(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        (, bytes16 acceptedAgreementId) = _withAcceptedIndexingAgreement(ctx, indexerStateA);

        // IndexerB tries to cancel indexerA's agreement
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNonCancelableBy.selector,
            indexerStateA.addr,
            indexerStateB.addr
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerStateB.addr);
        subgraphService.cancelIndexingAgreement(indexerStateB.addr, acceptedAgreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, _withIndexer(ctx));

        _cancelAgreement(
            ctx,
            acceptedAgreementId,
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }

    // solhint-disable-next-line graph/func-name-mixedcase
    /// @notice An indexer whose provision drops below minimum should still be able
    /// to cancel their indexing agreement. Cancel is an exit path.
    function test_SubgraphService_CancelIndexingAgreement_OK_WhenProvisionBelowMinimum(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 acceptedAgreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Thaw tokens to bring effective provision below minimum.
        // _withIndexer provisions at least MINIMUM_PROVISION_TOKENS, so thawing
        // (tokens - MINIMUM_PROVISION_TOKENS + 1) puts us 1 below the floor.
        uint256 thawAmount = indexerState.tokens - MINIMUM_PROVISION_TOKENS + 1;
        resetPrank(indexerState.addr);
        staking.thaw(indexerState.addr, address(subgraphService), thawAmount);

        // Verify provision is now below minimum
        uint256 effectiveTokens = indexerState.tokens - thawAmount;
        assertLt(effectiveTokens, MINIMUM_PROVISION_TOKENS);

        // Cancel should succeed despite invalid provision
        _cancelAgreement(
            ctx,
            acceptedAgreementId,
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}
