// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementUpgradeTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_UpdateIndexingAgreementIndexingAgreement_Revert_WhenPaused(
        address operator,
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau,
        bytes calldata authData
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.updateIndexingAgreement(operator, rcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAuthorized(
        address indexer,
        address notAuthorized,
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau,
        bytes calldata authData
    ) public withSafeIndexerOrOperator(notAuthorized) {
        vm.assume(notAuthorized != indexer);
        resetPrank(notAuthorized);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            notAuthorized
        );
        vm.expectRevert(expectedErr);
        subgraphService.updateIndexingAgreement(indexer, rcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        bytes memory authData
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
        subgraphService.updateIndexingAgreement(indexer, rcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        bytes memory authData
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
        subgraphService.updateIndexingAgreement(indexer, rcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau,
            bytes memory authData
        ) = _generateAcceptableSignedRCAU(ctx, _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr));

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptableRcau.agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, acceptableRcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAuthorizedForAgreement(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerStateA
        );
        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau,
            bytes memory authData
        ) = _generateAcceptableSignedRCAU(ctx, acceptedRca);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotAuthorized.selector,
            acceptableRcau.agreementId,
            indexerStateB.addr
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerStateB.addr);
        subgraphService.updateIndexingAgreement(indexerStateB.addr, acceptableRcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate
            memory acceptableUpdate = _generateAcceptableRecurringCollectionAgreementUpdate(ctx, acceptedRca);
        acceptableUpdate.metadata = bytes("invalid");
        // Set correct nonce for first update (should be 1)
        acceptableUpdate.nonce = 1;
        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory unacceptableRcau,
            bytes memory authData
        ) = _recurringCollectorHelper.generateSignedRCAU(acceptableUpdate, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAUMetadata",
            unacceptableRcau.metadata
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, unacceptableRcau, authData);
    }

    function test_SubgraphService_UpdateIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau,
            bytes memory authData
        ) = _generateAcceptableSignedRCAU(ctx, acceptedRca);

        IndexingAgreement.UpdateIndexingAgreementMetadata memory metadata = abi.decode(
            acceptableRcau.metadata,
            (IndexingAgreement.UpdateIndexingAgreementMetadata)
        );

        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementUpdated(
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            acceptableRcau.agreementId,
            indexerState.allocationId,
            metadata.version,
            metadata.terms
        );

        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, acceptableRcau, authData);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
