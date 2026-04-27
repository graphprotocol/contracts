// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

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
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        bytes calldata authData
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIndexingAgreement(allocationId, rca, authData);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotAuthorized(
        address allocationId,
        address operator,
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        bytes calldata authData
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != rca.serviceProvider);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            rca.serviceProvider,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, rca, authData);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        bytes memory authData
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            MINIMUM_PROVISION_TOKENS,
            MAXIMUM_PROVISION_TOKENS
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, rca, authData);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        bytes memory authData
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        rca.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, rca, authData);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotDataService(
        Seed memory seed,
        address incorrectDataService
    ) public {
        vm.assume(incorrectDataService != address(subgraphService));

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptableRca, ) = _generateAcceptableSignedRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.dataService = incorrectDataService;
        (
            IRecurringCollector.RecurringCollectionAgreement memory unacceptableRca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(acceptableRca, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementWrongDataService.selector,
            address(subgraphService),
            unacceptableRca.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptableRca, ) = _generateAcceptableSignedRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.metadata = bytes("invalid");
        (
            IRecurringCollector.RecurringCollectionAgreement memory unacceptableRca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(acceptableRca, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAMetadata",
            unacceptableRca.metadata
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidAllocation(
        Seed memory seed,
        address invalidAllocationId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptableRca,
            bytes memory signature
        ) = _generateAcceptableSignedRCA(ctx, indexerState.addr);

        bytes memory expectedErr = abi.encodeWithSelector(
            IAllocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(invalidAllocationId, acceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationNotAuthorized(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptableRcaA,
            bytes memory signatureA
        ) = _generateAcceptableSignedRCA(ctx, indexerStateA.addr);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            indexerStateA.addr,
            indexerStateB.allocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerStateA.addr);
        subgraphService.acceptIndexingAgreement(indexerStateB.allocationId, acceptableRcaA, signatureA);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationClosed(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptableRca,
            bytes memory signature
        ) = _generateAcceptableSignedRCA(ctx, indexerState.addr);

        resetPrank(indexerState.addr);
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationHandler.AllocationHandlerAllocationClosed.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, acceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenDeploymentIdMismatch(
        Seed memory seed,
        bytes32 wrongSubgraphDeploymentId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        vm.assume(indexerState.subgraphDeploymentId != wrongSubgraphDeploymentId);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptableRca, ) = _generateAcceptableSignedRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.metadata = abi.encode(_newAcceptIndexingAgreementMetadataV1(wrongSubgraphDeploymentId));
        (
            IRecurringCollector.RecurringCollectionAgreement memory unacceptableRca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(acceptableRca, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementDeploymentIdMismatch.selector,
            wrongSubgraphDeploymentId,
            indexerState.allocationId,
            indexerState.subgraphDeploymentId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Idempotent_WhenAlreadyAcceptedSameAllocation(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Re-sign for the re-accept (the original signature was consumed)
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(
            acceptedRca,
            ctx.payer.signerPrivateKey
        );

        // Re-accepting the same RCA on the same allocation is a no-op.
        resetPrank(ctx.indexers[0].addr);
        bytes16 returnedId = subgraphService.acceptIndexingAgreement(
            ctx.indexers[0].allocationId,
            acceptedRca,
            signature
        );
        assertEq(returnedId, agreementId);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAllocated(
        Seed memory seed,
        uint256 alternativeNonce
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);

        // First, accept an indexing agreement on the allocation
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        vm.assume(acceptedRca.nonce != alternativeNonce);

        // Now try to accept a different agreement on the same allocation
        // Create a new agreement with different nonce to ensure different agreement ID
        IRecurringCollector.RecurringCollectionAgreement
            memory newRCA = _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr);
        newRCA.nonce = alternativeNonce; // Different nonce to ensure different agreement ID

        // Sign the new agreement
        (
            IRecurringCollector.RecurringCollectionAgreement memory newSignedRca,
            bytes memory newSignature
        ) = _recurringCollectorHelper.generateSignedRCA(newRCA, ctx.payer.signerPrivateKey);

        // Expect the error when trying to accept a second agreement on the same allocation
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.AllocationAlreadyHasIndexingAgreement.selector,
            indexerState.allocationId
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, newSignedRca, newSignature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidTermsData(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptableRca, ) = _generateAcceptableSignedRCA(
            ctx,
            indexerState.addr
        );
        // forge-lint: disable-next-line(mixed-case-variable)
        IRecurringCollector.RecurringCollectionAgreement memory notAcceptableRCA = acceptableRca;
        bytes memory invalidTermsData = bytes("invalid terms data");
        notAcceptableRCA.metadata = abi.encode(
            _newAcceptIndexingAgreementMetadataV1Terms(indexerState.subgraphDeploymentId, invalidTermsData)
        );
        (
            IRecurringCollector.RecurringCollectionAgreement memory notAcceptableRcaSigned,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(notAcceptableRCA, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeIndexingAgreementTermsV1",
            invalidTermsData
        );
        vm.expectRevert(expectedErr);
        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, notAcceptableRcaSigned, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenTermsExceedRCALimit(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptableRca, ) = _generateAcceptableSignedRCA(
            ctx,
            indexerState.addr
        );

        // Override metadata with tokensPerSecond exceeding RCA maxOngoingTokensPerSecond
        uint256 excessiveTokensPerSecond = acceptableRca.maxOngoingTokensPerSecond + 1;
        acceptableRca.metadata = _encodeAcceptIndexingAgreementMetadataV1(
            indexerState.subgraphDeploymentId,
            IndexingAgreement.IndexingAgreementTermsV1({
                tokensPerSecond: excessiveTokensPerSecond,
                tokensPerEntityPerSecond: 0
            })
        );
        (
            IRecurringCollector.RecurringCollectionAgreement memory unacceptableRca,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCA(acceptableRca, ctx.payer.signerPrivateKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementInvalidTerms.selector,
            excessiveTokensPerSecond,
            unacceptableRca.maxOngoingTokensPerSecond
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, unacceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptableRca,
            bytes memory signature
        ) = _generateAcceptableSignedRCA(ctx, indexerState.addr);
        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = abi.decode(
            acceptableRca.metadata,
            (IndexingAgreement.AcceptIndexingAgreementMetadata)
        );
        // Generate deterministic agreement ID for event expectation
        bytes16 expectedAgreementId = recurringCollector.generateAgreementId(
            acceptableRca.payer,
            acceptableRca.dataService,
            acceptableRca.serviceProvider,
            acceptableRca.deadline,
            acceptableRca.nonce
        );

        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementAccepted(
            acceptableRca.serviceProvider,
            acceptableRca.payer,
            expectedAgreementId,
            indexerState.allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );

        resetPrank(indexerState.addr);
        subgraphService.acceptIndexingAgreement(indexerState.allocationId, acceptableRca, signature);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Rebinds_WhenDifferentAllocation(
        Seed memory seed,
        uint256 secondAllocationKey
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // Agreement is now bound to the first allocation.
        IIndexingAgreement.AgreementWrapper memory before = subgraphService.getIndexingAgreement(agreementId);
        assertEq(before.agreement.allocationId, indexerState.allocationId, "starts bound to first allocation");

        // Derive a second allocation for the same indexer + same subgraph deployment. The first
        // allocation already consumed the indexer's provision, so top up first.
        uint256 extraTokens = 10_000_000 ether;
        deal({ token: address(token), to: indexerState.addr, give: extraTokens });
        resetPrank(indexerState.addr);
        _addToProvision(indexerState.addr, extraTokens);

        secondAllocationKey = boundKey(secondAllocationKey);
        address secondAllocationId = vm.addr(secondAllocationKey);
        vm.assume(secondAllocationId != indexerState.allocationId);
        vm.assume(ctx.allocations[secondAllocationId] == address(0));
        ctx.allocations[secondAllocationId] = indexerState.addr;

        bytes memory allocData = _createSubgraphAllocationData(
            indexerState.addr,
            indexerState.subgraphDeploymentId,
            secondAllocationKey,
            extraTokens
        );
        _startService(indexerState.addr, allocData);

        // Re-sign the same RCA (original signature was consumed on first accept).
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(
            acceptedRca,
            ctx.payer.signerPrivateKey
        );

        // Re-accepting the same agreement on the new allocation rebinds it:
        // event is re-emitted, agreement.allocationId updates, old allocation's active-agreement
        // mapping is cleared. Collector's accept() is a no-op (already Accepted).
        IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata = abi.decode(
            acceptedRca.metadata,
            (IndexingAgreement.AcceptIndexingAgreementMetadata)
        );
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementAccepted(
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            agreementId,
            secondAllocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );
        resetPrank(indexerState.addr);
        bytes16 returnedId = subgraphService.acceptIndexingAgreement(secondAllocationId, acceptedRca, signature);
        assertEq(returnedId, agreementId, "rebind returns same agreementId");

        IIndexingAgreement.AgreementWrapper memory rebound = subgraphService.getIndexingAgreement(agreementId);
        assertEq(rebound.agreement.allocationId, secondAllocationId, "rebound to second allocation");
        assertEq(
            uint8(rebound.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "collector state still Accepted after rebind"
        );

        // Closing the OLD allocation must not cancel the agreement — the agreement no longer
        // points to it. onCloseAllocation's allocationToActiveAgreementId lookup should return 0.
        resetPrank(indexerState.addr);
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));

        IIndexingAgreement.AgreementWrapper memory afterOldClose = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            uint8(afterOldClose.collectorAgreement.state),
            uint8(IRecurringCollector.AgreementState.Accepted),
            "closing old allocation leaves agreement intact"
        );
        assertEq(afterOldClose.agreement.allocationId, secondAllocationId, "still bound to second allocation");
    }
    /* solhint-enable graph/func-name-mixedcase */
}
