// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    REGISTERED,
    ACCEPTED,
    SETTLED
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { Vm } from "forge-std/Vm.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";

import { IndexingAgreement } from "../../../../contracts/libraries/IndexingAgreement.sol";
import { AllocationHandler } from "../../../../contracts/libraries/AllocationHandler.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

/// @title Allocation-Agreement Lifecycle Tests
/// @notice Tests for the redesigned allocation-agreement lifecycle:
///   - SETTLED-gated allocation close (decision 2)
///   - Bidirectional mapping integrity (decision 1)
///   - Allocation rebinding via extraData (decision 3)
///   - Revival gating (decisions 3/5)
contract AllocationAgreementLifecycleTest is SubgraphServiceIndexingAgreementSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    //  Helpers
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Offer and accept a first update, then return an RCAU for a second update
    ///      with the same metadata. This ensures activeTerms.metadata is in Update format
    ///      so a subsequent same-metadata RCAU triggers the skip path.
    function _withFirstUpdateThenSameMetadataRCAU(
        Context storage _ctx,
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes16 _agreementId,
        address _indexer
    ) internal returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2) {
        // First update: sets activeTerms.metadata to UpdateMetadata format
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _generateAcceptableRCAU(_ctx, _rca);

        resetPrank(_rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(_agreementId, 1).versionHash;
        resetPrank(_indexer);
        recurringCollector.accept(_agreementId, pendingHash, bytes(""), 0);

        // Second update: same metadata as first → should trigger skip
        rcau2 = _generateAcceptableRCAU(_ctx, _rca);
        rcau2.nonce = rcau1.nonce + 1;
        rcau2.metadata = rcau1.metadata; // same metadata as now-active terms
    }

    // ══════════════════════════════════════════════════════════════════════
    //  SETTLED-gated allocation close (decision 2)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice close-before-settled → rejected when guard enabled
    function test_CloseAllocation_RevertsWhenNotSettled(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexer);

        resetPrank(users.governor);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);

        resetPrank(indexer.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationHasActiveAgreement.selector,
                indexer.allocationId,
                agreementId
            )
        );
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));
    }

    /// @notice close-after-settled → allowed, both mappings cleared
    function test_CloseAllocation_SucceedsWhenSettled(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        resetPrank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, address(0), "agreement.allocationId should be cleared");
    }

    /// @notice close-before-settled with guard → SubgraphServiceAllocationHasActiveAgreement
    function test_CloseAllocation_GuardRejectsActiveAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexer);

        resetPrank(users.governor);
        subgraphService.setBlockClosingAllocationWithActiveAgreement(true);

        resetPrank(indexer.addr);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationHasActiveAgreement.selector,
                indexer.allocationId,
                agreementId
            )
        );
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Rebinding via extraData (decision 3)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice rebind to same allocation → no-op, accepted
    function test_Rebind_ToSameAllocation_NoOp(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(indexer.allocationId), 0);

        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, indexer.allocationId, "allocationId should be unchanged");
    }

    /// @notice second agreement attempting to bind to an already-bound allocation → rejected
    function test_SecondAgreement_BindToAlreadyBoundAllocation_Rejected(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        _withAcceptedIndexingAgreement(ctx, indexer);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _generateAcceptableRCA(ctx, indexer.addr);
        // Shift deadline to produce a different agreementId (deadline is part of the ID hash)
        rca2.deadline = rca2.deadline + 1;

        resetPrank(rca2.payer);
        bytes16 agreementId2 = recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca2), 0).agreementId;

        bytes32 versionHash = recurringCollector.getAgreementDetails(agreementId2, 0).versionHash;
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexingAgreement.AllocationAlreadyHasIndexingAgreement.selector,
                indexer.allocationId
            )
        );
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId2, versionHash, abi.encode(indexer.allocationId), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Revival and SETTLED transitions (decisions 3/5)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice BY_PROVIDER cancel (SETTLED) + same-terms update → acceptAgreement called (revival)
    function test_Revival_AfterByProviderCancel_AcceptAgreementCalled(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        // After cancel, do first update + then same-metadata second update to
        // ensure activeTerms.metadata format matches for the skip comparison.
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Accept — agreement is SETTLED so acceptAgreement MUST be called regardless of metadata
        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        vm.recordLogs();
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // Verify acceptAgreement was called by checking for IndexingAgreementUpdated event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 updatedSig = IndexingAgreement.IndexingAgreementUpdated.selector;
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == updatedSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "IndexingAgreementUpdated should be emitted on SETTLED revival");

        // Agreement should be active again
        IRecurringCollector.AgreementData memory data = recurringCollector.getAgreementData(agreementId);
        assertEq(data.state & SETTLED, 0, "SETTLED should be cleared after revival");
        assertEq(data.state & ACCEPTED, ACCEPTED, "ACCEPTED should be set");
    }

    /// @notice revival-after-SETTLED with allocation still open → allowed without new allocationId
    function test_Revival_AllocationStillOpen_NoRebindNeeded(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Cancel BY_PROVIDER → SETTLED, but allocation mapping NOT cleared (decision 1)
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Accept without extraData — allocation is still open and bound
        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, indexer.allocationId, "should still be bound to original allocation");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  acceptAgreement skip on no-op update (decision 5 — collector-side)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice update with metadata unchanged, no extraData, not SETTLED → acceptAgreement not called
    function test_NoOpUpdate_SkipsAcceptAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // First update to set activeTerms.metadata in Update format, then second with same metadata
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _withFirstUpdateThenSameMetadataRCAU(
            ctx,
            rca,
            agreementId,
            indexer.addr
        );

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        vm.recordLogs();
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // IndexingAgreementUpdated should NOT be present (acceptAgreement was skipped)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 updatedSig = IndexingAgreement.IndexingAgreementUpdated.selector;
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == updatedSig) {
                found = true;
                break;
            }
        }
        assertFalse(found, "IndexingAgreementUpdated should NOT be emitted when acceptAgreement is skipped");
    }

    /// @notice update with metadata unchanged but extraData present → acceptAgreement called
    function test_Update_WithExtraData_ForcesAcceptAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // First update to set activeTerms.metadata in Update format, then same metadata
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _withFirstUpdateThenSameMetadataRCAU(
            ctx,
            rca,
            agreementId,
            indexer.addr
        );

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        vm.recordLogs();
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(indexer.allocationId), 0);

        // IndexingAgreementUpdated SHOULD be present (extraData forces callback)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 updatedSig = IndexingAgreement.IndexingAgreementUpdated.selector;
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == updatedSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "IndexingAgreementUpdated should be emitted when extraData is present");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Rebind to different allocation (decision 3)
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Create a second allocation for the same indexer by adding tokens to their provision.
    ///      Derives a deterministic, collision-free allocation key using makeAddrAndKey.
    function _withSecondAllocation(IndexerState memory _indexer) internal returns (address newAllocationId) {
        (address allocId, uint256 allocationKey) = makeAddrAndKey(
            string.concat("secondAllocation-", vm.toString(_indexer.addr))
        );
        newAllocationId = allocId;

        uint256 tokens = MINIMUM_PROVISION_TOKENS;
        mint(_indexer.addr, tokens);

        resetPrank(_indexer.addr);
        token.approve(address(staking), tokens);
        staking.stakeTo(_indexer.addr, tokens);
        staking.addToProvision(_indexer.addr, address(subgraphService), tokens);

        bytes memory data = _createSubgraphAllocationData(
            _indexer.addr,
            _indexer.subgraphDeploymentId,
            allocationKey,
            tokens
        );
        subgraphService.startService(_indexer.addr, data);
    }

    /// @notice rebind to new allocation while old allocation still open → allowed, old mapping cleared
    function test_Rebind_ToNewAllocation_WhileOldOpen(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        address newAllocationId = _withSecondAllocation(indexer);

        // Offer update, accept with new allocation in extraData
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(newAllocationId), 0);

        // Verify agreement is now bound to new allocation
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, newAllocationId, "should be bound to new allocation");
    }

    /// @notice rebind to new allocation after close → allowed, old mapping cleared, new mapping set
    function test_Rebind_ToNewAllocation_AfterClose(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Cancel BY_PROVIDER → SETTLED
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        // Close old allocation (SETTLED, so allowed)
        resetPrank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        // Create second allocation
        address newAllocationId = _withSecondAllocation(indexer);

        // Offer update to revive, accept with new allocation
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(newAllocationId), 0);

        // Verify agreement is now bound to new allocation
        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, newAllocationId, "should be bound to new allocation");
    }

    /// @notice rebind to closed allocation → rejected (new allocation must be open)
    function test_Rebind_ToClosedAllocation_Rejected(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Create second allocation, then close it
        address closedAllocationId = _withSecondAllocation(indexer);

        // Cancel the agreement BY_PROVIDER so we can close the second allocation
        // (the second allocation is not bound to any agreement, so we just close it directly)
        resetPrank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(closedAllocationId));

        // Now try to rebind the agreement to the closed allocation
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.expectRevert(
            abi.encodeWithSelector(AllocationHandler.AllocationHandlerAllocationClosed.selector, closedAllocationId)
        );
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(closedAllocationId), 0);
    }

    /// @notice BY_PROVIDER cancel (SETTLED) + update with new allocation → service resumes
    function test_Revival_WithNewAllocation_AfterByProviderCancel(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Cancel BY_PROVIDER → SETTLED
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        // Create second allocation
        address newAllocationId = _withSecondAllocation(indexer);

        // Offer update with new allocation to revive service on different allocation
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(newAllocationId), 0);

        // Verify agreement is revived and bound to new allocation
        IRecurringCollector.AgreementData memory data = recurringCollector.getAgreementData(agreementId);
        assertEq(data.state & SETTLED, 0, "SETTLED should be cleared");
        assertEq(data.state & ACCEPTED, ACCEPTED, "ACCEPTED should be set");

        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(wrapper.agreement.allocationId, newAllocationId, "should be bound to new allocation");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Cross-deployment rebinding after allocation close (audit #1)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice After allocation close clears allocationId to address(0), rebinding to
    ///         a different subgraph deployment must still be rejected.
    function test_Rebind_AfterClose_ToDifferentDeployment_Rejected(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        // Cancel BY_PROVIDER → SETTLED
        _cancelAgreement(ctx, agreementId, indexer.addr, rca.payer, true);

        // Close old allocation (SETTLED, so allowed) — clears agreement.allocationId to address(0)
        resetPrank(indexer.addr);
        subgraphService.stopService(indexer.addr, abi.encode(indexer.allocationId));

        IIndexingAgreement.AgreementWrapper memory wrapperAfterClose = subgraphService.getIndexingAgreement(
            agreementId
        );
        assertEq(wrapperAfterClose.agreement.allocationId, address(0), "allocationId should be cleared after close");

        // Create a second allocation on a DIFFERENT subgraph deployment
        bytes32 differentDeploymentId = keccak256(abi.encode(indexer.subgraphDeploymentId, "different"));
        (address diffAllocId, uint256 diffAllocKey) = makeAddrAndKey(
            string.concat("diffDeployAlloc-", vm.toString(indexer.addr))
        );

        uint256 tokens = MINIMUM_PROVISION_TOKENS;
        mint(indexer.addr, tokens);
        resetPrank(indexer.addr);
        token.approve(address(staking), tokens);
        staking.stakeTo(indexer.addr, tokens);
        staking.addToProvision(indexer.addr, address(subgraphService), tokens);

        bytes memory allocData = _createSubgraphAllocationData(
            indexer.addr,
            differentDeploymentId,
            diffAllocKey,
            tokens
        );
        subgraphService.startService(indexer.addr, allocData);

        // Attempt to rebind to the allocation on a different deployment — must revert
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);
        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexingAgreement.IndexingAgreementDeploymentIdMismatch.selector,
                indexer.subgraphDeploymentId,
                diffAllocId,
                differentDeploymentId
            )
        );
        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, abi.encode(diffAllocId), 0);
    }

    /// @notice Verify stored subgraphDeploymentId is accessible after accept
    function test_Accept_StoresSubgraphDeploymentId(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (, bytes16 agreementId) = _withAcceptedIndexingAgreement(ctx, indexer);

        IIndexingAgreement.AgreementWrapper memory wrapper = subgraphService.getIndexingAgreement(agreementId);
        assertEq(
            wrapper.agreement.subgraphDeploymentId,
            indexer.subgraphDeploymentId,
            "subgraphDeploymentId should be stored on State at initial accept"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Metadata-based skip / force (decision 5)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice update with different metadata, no extraData, not SETTLED → acceptAgreement called
    function test_Update_MetadataChanged_CallsAcceptAgreement(Seed memory seed) public {
        Context storage ctx = _newCtx(seed);
        IndexerState memory indexer = _withIndexer(ctx);
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
            bytes16 agreementId
        ) = _withAcceptedIndexingAgreement(ctx, indexer);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _generateAcceptableRCAU(ctx, rca);

        resetPrank(rca.payer);
        recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        IndexingAgreement.UpdateIndexingAgreementMetadata memory meta = abi.decode(
            rcau.metadata,
            (IndexingAgreement.UpdateIndexingAgreementMetadata)
        );
        vm.expectEmit(address(subgraphService));
        emit IndexingAgreement.IndexingAgreementUpdated(
            indexer.addr,
            rca.payer,
            agreementId,
            indexer.allocationId,
            meta.version,
            meta.terms
        );

        resetPrank(indexer.addr);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
