// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";

import { Allocation } from "../../../../contracts/libraries/Allocation.sol";
import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";
import { AllocationHandler } from "../../../../contracts/libraries/AllocationHandler.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

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
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        signedRCA.rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            MINIMUM_PROVISION_TOKENS,
            MAXIMUM_PROVISION_TOKENS
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
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        signedRCA.rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotDataService(
        Seed memory seed,
        address incorrectDataService
    ) public {
        vm.assume(incorrectDataService != address(subgraphService));

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        acceptable.rca.dataService = incorrectDataService;
        IRecurringCollector.SignedRCA memory unacceptable = _recurringCollectorHelper.generateSignedRCA(
            acceptable.rca,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementWrongDataService.selector,
            address(subgraphService),
            unacceptable.rca.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        acceptable.rca.metadata = bytes("invalid");
        IRecurringCollector.SignedRCA memory unacceptable = _recurringCollectorHelper.generateSignedRCA(
            acceptable.rca,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAMetadata",
            unacceptable.rca.metadata
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidAllocation(
        Seed memory seed,
        address invalidAllocationId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAllocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(invalidAllocationId, acceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationNotAuthorized(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptableA = _generateAcceptableSignedRCA(ctx, indexerStateA.addr);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            indexerStateA.addr,
            indexerStateB.allocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerStateA.addr);
        subgraphService.acceptIndexingAgreement(indexerStateB.allocationId, acceptableA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationClosed(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);

        resetPrank(indexerState.addr);
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationHandler.AllocationHandlerAllocationClosed.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, acceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenDeploymentIdMismatch(
        Seed memory seed,
        bytes32 wrongSubgraphDeploymentId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        vm.assume(indexerState.subgraphDeploymentId != wrongSubgraphDeploymentId);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        acceptable.rca.metadata = abi.encode(_newAcceptIndexingAgreementMetadataV1(wrongSubgraphDeploymentId));
        IRecurringCollector.SignedRCA memory unacceptable = _recurringCollectorHelper.generateSignedRCA(
            acceptable.rca,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementDeploymentIdMismatch.selector,
            wrongSubgraphDeploymentId,
            indexerState.allocationId,
            indexerState.subgraphDeploymentId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.SignedRCA memory accepted, bytes16 agreementId) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementAlreadyAccepted.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(ctx.indexers[0].addr);
        subgraphService.acceptIndexingAgreement(ctx.indexers[0].allocationId, accepted);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAllocated(
        Seed memory seed,
        uint256 alternativeNonce
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        // First, accept an indexing agreement on the allocation
        (IRecurringCollector.SignedRCA memory accepted, ) = _withAcceptedIndexingAgreement(ctx, indexerState);
        vm.assume(accepted.rca.nonce != alternativeNonce);

        // Now try to accept a different agreement on the same allocation
        // Create a new agreement with different nonce to ensure different agreement ID
        IRecurringCollector.RecurringCollectionAgreement
            memory newRCA = _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr);
        newRCA.nonce = alternativeNonce; // Different nonce to ensure different agreement ID

        // Sign the new agreement
        IRecurringCollector.SignedRCA memory newSignedRCA = _recurringCollectorHelper.generateSignedRCA(
            newRCA,
            ctx.payer.signerPrivateKey
        );

        // Expect the error when trying to accept a second agreement on the same allocation
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.AllocationAlreadyHasIndexingAgreement.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, newSignedRCA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidTermsData(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        IRecurringCollector.RecurringCollectionAgreement memory notAcceptableRCA = acceptable.rca;
        bytes memory invalidTermsData = bytes("invalid terms data");
        notAcceptableRCA.metadata = abi.encode(
            _newAcceptIndexingAgreementMetadataV1Terms(indexerState.subgraphDeploymentId, invalidTermsData)
        );
        IRecurringCollector.SignedRCA memory notAcceptable = _recurringCollectorHelper.generateSignedRCA(
            notAcceptableRCA,
            ctx.payer.signerPrivateKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeIndexingAgreementTermsV1",
            invalidTermsData
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, notAcceptable);
    }

    function test_SubgraphService_AcceptIndexingAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.SignedRCA memory acceptable = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = abi.decode(
            acceptable.rca.metadata,
            (IndexingAgreement.AcceptIndexingAgreementMetadata)
        );
        // Generate deterministic agreement ID for event expectation
        bytes16 expectedAgreementId = recurringCollector.generateAgreementId(
            acceptable.rca.payer,
            acceptable.rca.dataService,
            acceptable.rca.serviceProvider,
            acceptable.rca.deadline,
            acceptable.rca.nonce
        );

        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementAccepted(
            acceptable.rca.serviceProvider,
            acceptable.rca.payer,
            expectedAgreementId,
            indexerState.allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );

        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, acceptable);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
