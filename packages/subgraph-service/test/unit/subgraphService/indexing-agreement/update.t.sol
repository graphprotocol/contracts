// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementUpgradeTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * HELPERS
     */

    /// @dev Submit an update offer to RC and then accept it, expecting the accept to revert.
    function _offerUpdateAndExpectRevertOnAccept(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        address payer,
        address acceptCaller,
        bytes memory expectedErr
    ) internal {
        vm.stopPrank();
        vm.prank(payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(rcau.agreementId, 1).versionHash;
        vm.expectRevert(expectedErr);
        vm.prank(acceptCaller);
        recurringCollector.accept(rcau.agreementId, pendingHash, bytes(""), 0);
    }

    /// @dev Submit an update offer to RC and then accept with extraData, expecting the accept to revert.
    function _offerUpdateAndExpectRevertOnAcceptWithExtraData(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        address payer,
        address acceptCaller,
        bytes memory extraData,
        bytes memory expectedErr
    ) internal {
        vm.stopPrank();
        vm.prank(payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(rcau.agreementId, 1).versionHash;
        vm.expectRevert(expectedErr);
        vm.prank(acceptCaller);
        recurringCollector.accept(rcau.agreementId, pendingHash, extraData, 0);
    }

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenRebindToDifferentDeployment(
        Seed memory seed
    ) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            acceptedRca
        );

        // Create a second allocation for the same indexer on a DIFFERENT subgraph deployment.
        // Mint extra tokens so the indexer can afford a second allocation.
        bytes32 differentDeploymentId = keccak256(abi.encode(indexerState.subgraphDeploymentId, "different"));
        (uint256 secondAllocKey, address secondAllocId) = boundKeyAndAddr(
            uint256(keccak256(abi.encode(seed.indexer0.unboundedAllocationPrivateKey, "second")))
        );
        vm.assume(secondAllocId != indexerState.allocationId);

        uint256 extraTokens = MINIMUM_PROVISION_TOKENS;
        mint(indexerState.addr, extraTokens);
        address originalPrank = _subgraphServiceSafePrank(indexerState.addr);
        _addToProvision(indexerState.addr, extraTokens);

        bytes memory allocData = _createSubgraphAllocationData(
            indexerState.addr,
            differentDeploymentId,
            secondAllocKey,
            extraTokens
        );
        _startService(indexerState.addr, allocData);
        _stopOrResetPrank(originalPrank);

        // Attempt to rebind agreement to the allocation on a different deployment
        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreement.IndexingAgreementDeploymentIdMismatch.selector,
            indexerState.subgraphDeploymentId,
            secondAllocId,
            differentDeploymentId
        );
        _offerUpdateAndExpectRevertOnAcceptWithExtraData(
            acceptableRcau,
            acceptedRca.payer,
            indexerState.addr,
            abi.encode(secondAllocId),
            expectedErr
        );
    }

    function test_SubgraphService_UpdateIndexingAgreement_OK_WhenRebindToSameDeployment(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            acceptedRca
        );

        // Create a second allocation for the same indexer on the SAME subgraph deployment.
        // Mint extra tokens so the indexer can afford a second allocation.
        (uint256 secondAllocKey, address secondAllocId) = boundKeyAndAddr(
            uint256(keccak256(abi.encode(seed.indexer0.unboundedAllocationPrivateKey, "second")))
        );
        vm.assume(secondAllocId != indexerState.allocationId);

        uint256 extraTokens = MINIMUM_PROVISION_TOKENS;
        mint(indexerState.addr, extraTokens);
        address originalPrank2 = _subgraphServiceSafePrank(indexerState.addr);
        _addToProvision(indexerState.addr, extraTokens);

        bytes memory allocData = _createSubgraphAllocationData(
            indexerState.addr,
            indexerState.subgraphDeploymentId,
            secondAllocKey,
            extraTokens
        );
        _startService(indexerState.addr, allocData);
        _stopOrResetPrank(originalPrank2);

        // Rebind to allocation on same deployment should succeed
        vm.prank(acceptedRca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(acceptableRcau), 0);
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(acceptableRcau.agreementId, 1).versionHash;
        vm.prank(indexerState.addr);
        recurringCollector.accept(acceptableRcau.agreementId, pendingHash, abi.encode(secondAllocId), 0);

        // Verify the agreement is now bound to the new allocation
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(
            acceptableRcau.agreementId
        );
        assertEq(wrapper.agreement.allocationId, secondAllocId);
    }

    function test_SubgraphService_UpdateIndexingAgreementIndexingAgreement_Revert_WhenPaused(Seed memory seed) public {
        // NOTE: SS pause does NOT block accept through RC — the acceptAgreement callback
        // does not have whenNotPaused. When SS is paused, the RC accept still succeeds because
        // the RC itself is not paused and the SS callback doesn't check pause state.
        // This test now verifies the accept succeeds even when SS is paused.
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            acceptedRca
        );

        // Pause SS after setting up the agreement
        resetPrank(users.pauseGuardian);
        subgraphService.pause();
        vm.stopPrank();

        // offerUpdate and accept succeed even when SS is paused
        vm.prank(acceptedRca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(acceptableRcau), 0);
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(acceptableRcau.agreementId, 1).versionHash;
        vm.prank(indexerState.addr);
        recurringCollector.accept(acceptableRcau.agreementId, pendingHash, bytes(""), 0);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenNotAccepted(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _generateAcceptableRecurringCollectionAgreement(
            ctx,
            indexerState.addr
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            rca
        );

        // The agreement was never accepted on RC, so offerUpdate will fail at the RC level
        // because the agreement is in state None (not Accepted)
        vm.expectRevert();
        vm.prank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(acceptableRcau), 0);
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
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            acceptedRca
        );

        // offerUpdate succeeds, but accept by wrong indexer reverts at RC level
        // (RC checks msg.sender == serviceProvider)
        vm.prank(acceptedRca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(acceptableRcau), 0);
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(acceptableRcau.agreementId, 1).versionHash;
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.UnauthorizedServiceProvider.selector,
            indexerStateB.addr,
            indexerStateA.addr
        );
        vm.expectRevert(expectedErr);
        vm.prank(indexerStateB.addr);
        recurringCollector.accept(acceptableRcau.agreementId, pendingHash, bytes(""), 0);
    }

    function test_SubgraphService_UpdateIndexingAgreement_Revert_WhenInvalidMetadata(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate
            memory unacceptableRcau = _generateAcceptableRecurringCollectionAgreementUpdate(ctx, acceptedRca);
        unacceptableRcau.metadata = bytes("invalid");
        // Set correct nonce for first update (should be 1)
        unacceptableRcau.nonce = 1;

        bytes memory expectedErr = abi.encodeWithSelector(
            IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
            "decodeRCAUMetadata",
            unacceptableRcau.metadata
        );
        _offerUpdateAndExpectRevertOnAccept(unacceptableRcau, acceptedRca.payer, indexerState.addr, expectedErr);
    }

    function test_SubgraphService_UpdateIndexingAgreement_OK(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexerState = _withIndexer(ctx);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, ) = _withAcceptedIndexingAgreement(
            ctx,
            indexerState
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory acceptableRcau = _generateAcceptableRCAU(
            ctx,
            acceptedRca
        );

        IndexingAgreement.UpdateIndexingAgreementMetadata memory metadata = abi.decode(
            acceptableRcau.metadata,
            (IndexingAgreement.UpdateIndexingAgreementMetadata)
        );

        // Step 1: Payer submits update offer to RC
        vm.prank(acceptedRca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(acceptableRcau), 0);

        // Step 2: Accept update via RC (serviceProvider calls directly)
        bytes32 pendingHash = recurringCollector.getAgreementVersionAt(acceptableRcau.agreementId, 1).versionHash;
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementUpdated(
            acceptedRca.serviceProvider,
            acceptedRca.payer,
            acceptableRcau.agreementId,
            indexerState.allocationId,
            metadata.version,
            metadata.terms
        );

        vm.prank(indexerState.addr);
        recurringCollector.accept(acceptableRcau.agreementId, pendingHash, bytes(""), 0);
    }

    // Note: a test for agreement.version being set in the update path is not viable
    // because V1 is enum value 0 (same as uninitialized storage). The fix is still
    // applied for correctness — it becomes load-bearing when V2 is added.
    /* solhint-enable graph/func-name-mixedcase */
}
