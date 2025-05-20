// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { IndexingAgreement } from "../../../contracts/libraries/IndexingAgreement.sol";
import { Decoder } from "../../../contracts/libraries/Decoder.sol";

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
        _getSubgraphServiceExtension().upgradeIndexingAgreement(operator, signedRCAU);
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
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexer, signedRCAU);
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
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexer, signedRCAU);
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
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenNotAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCAU memory acceptableUpgrade = _generateAcceptableSignedRCAU(
            ctx,
            _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr)
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotActive.selector,
            acceptableUpgrade.rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexerState.addr, acceptableUpgrade);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenNotAuthorizedForAgreement(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerStateA);
        IRecurringCollector.SignedRCAU memory acceptableUpgrade = _generateAcceptableSignedRCAU(ctx, accepted.rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementNotAuthorized.selector,
            acceptableUpgrade.rcau.agreementId,
            indexerStateB.addr
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerStateB.addr);
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexerStateB.addr, acceptableUpgrade);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.RecurringCollectionAgreementUpgrade
            memory acceptableUpgrade = _generateAcceptableRecurringCollectionAgreementUpgrade(ctx, accepted.rca);
        acceptableUpgrade.metadata = bytes("invalid");
        IRecurringCollector.SignedRCAU memory unacceptableUpgrade = _recurringCollectorHelper.generateSignedRCAU(
            acceptableUpgrade,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            Decoder.DecoderInvalidData.selector,
            "decodeRCAUMetadata",
            unacceptableUpgrade.rcau.metadata
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexerState.addr, unacceptableUpgrade);
    }

    function test_SubgraphService_UpgradeIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory accepted = _withAcceptedIndexingAgreement(ctx, indexerState);
        IRecurringCollector.SignedRCAU memory acceptableUpgrade = _generateAcceptableSignedRCAU(ctx, accepted.rca);

        resetPrank(indexerState.addr);
        _getSubgraphServiceExtension().upgradeIndexingAgreement(indexerState.addr, acceptableUpgrade);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
