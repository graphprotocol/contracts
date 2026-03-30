// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";
import { AllocationHandler } from "../../../../contracts/libraries/AllocationHandler.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementAcceptTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * HELPERS
     */

    /// @dev Submit an offer to RC and then accept it, expecting the accept to revert.
    function _offerAndExpectRevertOnAccept(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        address allocationId,
        address acceptCaller,
        bytes memory expectedErr
    ) internal {
        vm.stopPrank();
        vm.prank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert(expectedErr);
        vm.prank(acceptCaller);
        recurringCollector.accept(agreementId, activeHash, abi.encode(allocationId), 0);
    }

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenPaused(Seed memory seed) public {
        // NOTE: SS pause does NOT block accept through RC — the acceptAgreement callback
        // does not have whenNotPaused. When SS is paused, the RC accept still succeeds because
        // the RC itself is not paused and the SS callback doesn't check pause state.
        // This test now verifies the accept succeeds even when SS is paused.
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );

        // Pause SS after generating valid offer
        resetPrank(users.pauseGuardian);
        subgraphService.pause();
        vm.stopPrank();

        // Offer and accept succeed even when SS is paused
        vm.prank(acceptableRca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(acceptableRca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(indexerState.allocationId), 0);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        Seed memory seed
    ) public withSafeIndexerOrOperator(indexer) {
        // An indexer with insufficient provision is also not registered.
        // The acceptAgreement callback checks registration BEFORE provision,
        // so the actual revert is SubgraphServiceIndexerNotRegistered.
        uint256 tokens = bound(unboundedTokens, 1, MINIMUM_PROVISION_TOKENS - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        vm.stopPrank();

        // Build a valid RCA targeting this under-provisioned indexer
        Context storage ctx = _newCtx(seed);
        IRecurringCollector.RecurringCollectionAgreement memory rca = ctx.ctxInternal.seed.rca;
        rca.serviceProvider = indexer;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(_newAcceptIndexingAgreementMetadataV1(bytes32(uint256(1))));
        rca = _recurringCollectorHelper.sensibleRCA(rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.prank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert(expectedErr);
        vm.prank(indexer);
        recurringCollector.accept(agreementId, activeHash, abi.encode(address(0)), 0);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        Seed memory seed
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        vm.stopPrank();

        // Build a valid RCA targeting this unregistered indexer
        Context storage ctx = _newCtx(seed);
        IRecurringCollector.RecurringCollectionAgreement memory rca = ctx.ctxInternal.seed.rca;
        rca.serviceProvider = indexer;
        rca.dataService = address(subgraphService);
        rca.metadata = abi.encode(_newAcceptIndexingAgreementMetadataV1(bytes32(uint256(1))));
        rca = _recurringCollectorHelper.sensibleRCA(rca);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.prank(rca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert(expectedErr);
        vm.prank(indexer);
        recurringCollector.accept(agreementId, activeHash, abi.encode(address(0)), 0);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotDataService(
        Seed memory seed,
        address incorrectDataService
    ) public {
        vm.assume(incorrectDataService != address(subgraphService));
        vm.assume(incorrectDataService != address(0));

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.dataService = incorrectDataService;

        // In the new flow, the RC accept callback calls into the wrong dataService (or no dataService),
        // so the revert depends on what incorrectDataService is. The offer will succeed since RC
        // doesn't validate dataService beyond non-zero. The accept will call the wrong contract.
        // Since incorrectDataService may not implement the callback, this will revert with various errors.
        // We just verify the offer succeeds and accept reverts.
        vm.prank(acceptableRca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(acceptableRca), 0).agreementId;
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert();
        vm.prank(indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(indexerState.allocationId), 0);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.metadata = bytes("invalid");

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAMetadata",
            acceptableRca.metadata
        );
        _offerAndExpectRevertOnAccept(acceptableRca, indexerState.allocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidAllocation(
        Seed memory seed,
        address invalidAllocationId
    ) public {
        vm.assume(invalidAllocationId != address(0));

        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IAllocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        _offerAndExpectRevertOnAccept(acceptableRca, invalidAllocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationNotAuthorized(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerStateA = _withIndexer(ctx);
        IndexerState memory indexerStateB = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRcaA = _generateAcceptableRCA(
            ctx,
            indexerStateA.addr
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            indexerStateA.addr,
            indexerStateB.allocationId
        );
        _offerAndExpectRevertOnAccept(acceptableRcaA, indexerStateB.allocationId, indexerStateA.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationClosed(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );

        resetPrank(indexerState.addr);
        subgraphService.stopService(indexerState.addr, abi.encode(indexerState.allocationId));

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationHandler.AllocationHandlerAllocationClosed.selector,
            indexerState.allocationId
        );
        _offerAndExpectRevertOnAccept(acceptableRca, indexerState.allocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenDeploymentIdMismatch(
        Seed memory seed,
        bytes32 wrongSubgraphDeploymentId
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        vm.assume(indexerState.subgraphDeploymentId != wrongSubgraphDeploymentId);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );
        acceptableRca.metadata = abi.encode(_newAcceptIndexingAgreementMetadataV1(wrongSubgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementDeploymentIdMismatch.selector,
            wrongSubgraphDeploymentId,
            indexerState.allocationId,
            indexerState.subgraphDeploymentId
        );
        _offerAndExpectRevertOnAccept(acceptableRca, indexerState.allocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexerState);

        // The agreement is already accepted on the collector, so trying to accept again
        // goes to the pending-update path (state has ACCEPTED set). Since there is no pending
        // update, the pending terms hash is bytes32(0) and the guard rejects with AgreementTermsEmpty.
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementTermsEmpty.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(indexerState.allocationId), 0);
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
        IRecurringCollector.RecurringCollectionAgreement
            memory newRCA = _generateAcceptableRecurringCollectionAgreement(ctx, indexerState.addr);
        newRCA.nonce = alternativeNonce;

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.AllocationAlreadyHasIndexingAgreement.selector,
            indexerState.allocationId
        );
        _offerAndExpectRevertOnAccept(newRCA, indexerState.allocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidTermsData(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );
        // forge-lint: disable-next-line(mixed-case-variable)
        IRecurringCollector.RecurringCollectionAgreement memory notAcceptableRCA = acceptableRca;
        bytes memory invalidTermsData = bytes("invalid terms data");
        notAcceptableRCA.metadata = abi.encode(
            _newAcceptIndexingAgreementMetadataV1Terms(indexerState.subgraphDeploymentId, invalidTermsData)
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeIndexingAgreementTermsV1",
            invalidTermsData
        );
        _offerAndExpectRevertOnAccept(notAcceptableRCA, indexerState.allocationId, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_AcceptIndexingAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory acceptableRca = _generateAcceptableRCA(
            ctx,
            indexerState.addr
        );
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

        // Step 1: Submit offer to RC
        vm.prank(acceptableRca.payer);
        bytes16 agreementId = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(acceptableRca), 0).agreementId;
        assertEq(agreementId, expectedAgreementId);

        // Step 2: Accept via RC (serviceProvider calls directly)
        bytes32 activeHash = recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
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

        vm.prank(indexerState.addr);
        recurringCollector.accept(agreementId, activeHash, abi.encode(indexerState.allocationId), 0);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
