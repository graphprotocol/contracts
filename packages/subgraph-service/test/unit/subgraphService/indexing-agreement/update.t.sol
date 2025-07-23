// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../../contracts/interfaces/ISubgraphService.sol";
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
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.updateIndexingAgreement(operator, signedRCAU);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAuthorized(
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
        subgraphService.updateIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
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
        subgraphService.updateIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, fishermanRewardPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.updateIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCAU memory acceptableUpdate = _generateAcceptableSignedRCAU(
            ctx,
            _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr)
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptableUpdate.rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, acceptableUpdate);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAuthorizedForAgreement(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerStateA);
        IRecurringCollector.SignedRCAU memory acceptableUpdate = _generateAcceptableSignedRCAU(ctx, accepted.rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotAuthorized.selector,
            acceptableUpdate.rcau.agreementId,
            indexerStateB.addr
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerStateB.addr);
        subgraphService.updateIndexingAgreement(indexerStateB.addr, acceptableUpdate);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.RecurringCollectionAgreementUpdate
            memory acceptableUpdate = _generateAcceptableRecurringCollectionAgreementUpdate(ctx, accepted.rca);
        acceptableUpdate.metadata = bytes("invalid");
        // Set correct nonce for first update (should be 1)
        acceptableUpdate.nonce = 1;
        IRecurringCollector.SignedRCAU memory unacceptableUpdate = _recurringCollectorHelper.generateSignedRCAU(
            acceptableUpdate,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAUMetadata",
            unacceptableUpdate.rcau.metadata
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, unacceptableUpdate);
    }

    function test_SubgraphService_UpdateIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.SignedRCAU memory acceptableUpdate = _generateAcceptableSignedRCAU(ctx, accepted.rca);

        IndexingAgreement.UpdateIndexingAgreementMetadata memory metadata = abi.decode(
            acceptableUpdate.rcau.metadata,
            (IndexingAgreement.UpdateIndexingAgreementMetadata)
        );

        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementUpdated(
            accepted.rca.serviceProvider,
            accepted.rca.payer,
            acceptableUpdate.rcau.agreementId,
            indexerState.allocationId,
            metadata.version,
            metadata.terms
        );

        resetPrank(indexerState.addr);
        subgraphService.updateIndexingAgreement(indexerState.addr, acceptableUpdate);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
