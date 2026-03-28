// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

/// @notice Edge case and boundary condition tests for RecurringAgreementManager.
contract RecurringAgreementManagerEdgeCasesTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== supportsInterface Fallback ====================

    function test_SupportsInterface_UnknownInterfaceReturnsFalse() public view {
        // Use a random interfaceId that doesn't match any supported interface
        // This exercises the super.supportsInterface() fallback (line 100)
        assertFalse(agreementManager.supportsInterface(bytes4(0xdeadbeef)));
    }

    function test_SupportsInterface_ERC165() public view {
        // ERC165 itself (0x01ffc9a7) is supported via super.supportsInterface()
        assertTrue(agreementManager.supportsInterface(type(IERC165).interfaceId));
    }

    // ==================== Cancel with Invalid Data Service ====================

    function test_CancelAgreement_Revert_WhenDataServiceHasNoCode() public {
        // Use an EOA as dataService so ds.code.length == 0 (line 255)
        address eoa = makeAddr("eoa-data-service");

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.dataService = eoa;

        // Grant DATA_SERVICE_ROLE so the offer goes through
        vm.prank(governor);
        agreementManager.grantRole(DATA_SERVICE_ROLE, eoa);

        token.mint(address(agreementManager), 1_000_000 ether);
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(rca, _collector());

        // Set as Accepted so it takes the cancel-via-dataService path
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: eoa,
                payer: address(agreementManager),
                serviceProvider: indexer,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IRecurringAgreementManagement.InvalidDataService.selector, eoa));
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    // ==================== Hash Cleanup Tests ====================

    function test_RevokeOffer_CleansUpAgreementHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        bytes32 rcaHash = recurringCollector.hashRCA(rca);

        // Hash is authorized
        assertEq(agreementManager.approveAgreement(rcaHash), IAgreementOwner.approveAgreement.selector);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        // Hash is cleaned up (not just stale — actually deleted)
        assertEq(agreementManager.approveAgreement(rcaHash), bytes4(0));
    }

    function test_RevokeOffer_CleansUpPendingUpdateHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        // Update hash is authorized
        assertEq(agreementManager.approveAgreement(updateHash), IAgreementOwner.approveAgreement.selector);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        // Both hashes cleaned up
        assertEq(agreementManager.approveAgreement(updateHash), bytes4(0));
    }

    function test_Remove_CleansUpAgreementHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        bytes32 rcaHash = recurringCollector.hashRCA(rca);

        // SP cancels — removable
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        // Hash is cleaned up
        assertEq(agreementManager.approveAgreement(rcaHash), bytes4(0));
    }

    function test_Remove_CleansUpPendingUpdateHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        bytes32 updateHash = recurringCollector.hashRCAU(rcau);

        // SP cancels — removable
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        // Pending update hash also cleaned up
        assertEq(agreementManager.approveAgreement(updateHash), bytes4(0));
    }

    function test_Reconcile_CleansUpAppliedPendingUpdateHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        assertEq(agreementManager.approveAgreement(updateHash), IAgreementOwner.approveAgreement.selector);

        // Simulate: agreement accepted with pending <= updateNonce (update was applied)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 7200,
                updateNonce: 1, // (pending <=)
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        agreementManager.reconcileAgreement(agreementId);

        // Pending update hash should be cleaned up after reconcile clears the applied update
        assertEq(agreementManager.approveAgreement(updateHash), bytes4(0));
    }

    function test_OfferUpdate_CleansUpReplacedPendingHash() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // First pending update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        bytes32 hash1 = recurringCollector.hashRCAU(rcau1);
        assertEq(agreementManager.approveAgreement(hash1), IAgreementOwner.approveAgreement.selector);

        // Second pending update replaces first (same nonce — collector hasn't accepted either)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            1
        );
        _offerAgreementUpdate(rcau2);

        // First update hash should be cleaned up
        assertEq(agreementManager.approveAgreement(hash1), bytes4(0));

        // Second update hash should be authorized
        bytes32 hash2 = recurringCollector.hashRCAU(rcau2);
        assertEq(agreementManager.approveAgreement(hash2), IAgreementOwner.approveAgreement.selector);
    }

    function test_GetAgreementInfo_IncludesHashes() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        bytes32 rcaHash = recurringCollector.hashRCA(rca);

        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.agreementHash, rcaHash);
        assertEq(info.pendingUpdateHash, bytes32(0));

        // Offer an update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        bytes32 updateHash = recurringCollector.hashRCAU(rcau);
        info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.agreementHash, rcaHash);
        assertEq(info.pendingUpdateHash, updateHash);
    }

    // ==================== Zero-Value Parameter Tests ====================

    function test_Offer_ZeroMaxInitialTokens() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            0, // zero initial tokens
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // maxNextClaim = 1e18 * 3600 + 0 = 3600e18
        uint256 expectedMaxClaim = 1 ether * 3600;
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), expectedMaxClaim);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), expectedMaxClaim);
    }

    function test_Offer_ZeroOngoingTokensPerSecond() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            0, // zero ongoing rate
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // maxNextClaim = 0 * 3600 + 100e18 = 100e18
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 100 ether);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 100 ether);
    }

    function test_Offer_AllZeroValues() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            0, // zero initial
            0, // zero ongoing
            0, // zero min seconds
            0, // zero max seconds
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // maxNextClaim = 0 * 0 + 0 = 0
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    // ==================== Deadline Boundary Tests ====================

    function test_Remove_AtExactDeadline_NotAccepted() public {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        // Override deadline (default from _makeRCA is block.timestamp + 1 hours, same as this)

        bytes16 agreementId = _offerAgreement(rca);

        // Warp to exactly the deadline
        vm.warp(deadline);

        // At deadline (block.timestamp == deadline), the condition is `block.timestamp <= info.deadline`
        // so this should still be claimable
        bool exists = agreementManager.reconcileAgreement(agreementId);
        assertTrue(exists);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    function test_Remove_OneSecondAfterDeadline_NotAccepted() public {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Warp to one second past deadline
        vm.warp(deadline + 1);

        // Now removable (deadline < block.timestamp)
        agreementManager.reconcileAgreement(agreementId);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);
    }

    // ==================== Reconcile Edge Cases ====================

    function test_Reconcile_WhenCollectionEndEqualsCollectionStart() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        uint64 now_ = uint64(block.timestamp);
        // Set as accepted with lastCollectionAt == endsAt (fully consumed)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: now_,
                lastCollectionAt: rca.endsAt,
                endsAt: rca.endsAt,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                updateNonce: 0,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        agreementManager.reconcileAgreement(agreementId);

        // getMaxNextClaim returns 0 when collectionEnd <= collectionStart
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    // ==================== Cancel Edge Cases ====================

    function test_CancelAgreement_Revert_WhenDataServiceReverts() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as accepted
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // Configure the mock SubgraphService to revert
        mockSubgraphService.setRevert(true, "SubgraphService: cannot cancel");

        vm.expectRevert("SubgraphService: cannot cancel");
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    // ==================== Offer With Zero Balance Tests ====================

    function test_Offer_ZeroTokenBalance_PartialFunding() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // Don't fund the contract — zero token balance
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(rca, _collector());

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Agreement is tracked even though escrow couldn't be funded
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), maxClaim);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);

        // Escrow has zero balance
        (uint256 escrowBal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBal, 0);

        // Escrow balance is 0
        assertEq(agreementManager.getEscrowAccount(_collector(), indexer).balance, 0);
    }

    // ==================== ReconcileBatch Edge Cases ====================

    function test_ReconcileBatch_InterleavedDuplicateIndexers() public {
        // Create agreements for two different indexers, interleaved
        address indexer2 = makeAddr("indexer2");

        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 365 days)
        );
        rca3.nonce = 3;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);
        bytes16 id3 = _offerAgreement(rca3);

        // Accept all, then SP-cancel all
        _setAgreementCanceledBySP(id1, rca1);
        _setAgreementCanceledBySP(id2, rca2);
        _setAgreementCanceledBySP(id3, rca3);

        // Interleaved order: indexer, indexer2, indexer
        // The lastFunded optimization won't catch the second indexer occurrence
        bytes16[] memory ids = new bytes16[](3);
        ids[0] = id1;
        ids[1] = id2;
        ids[2] = id3;

        // Should succeed without error — _fundEscrow is idempotent
        agreementHelper.reconcileBatch(ids);

        // All reconciled to 0
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), 0);
    }

    function test_ReconcileBatch_EmptyArray() public {
        // Empty batch should succeed with no effect
        bytes16[] memory ids = new bytes16[](0);
        agreementHelper.reconcileBatch(ids);
    }

    function test_ReconcileBatch_NonExistentAgreements() public {
        // Batch with non-existent IDs should skip silently
        bytes16[] memory ids = new bytes16[](2);
        ids[0] = bytes16(keccak256("nonexistent1"));
        ids[1] = bytes16(keccak256("nonexistent2"));

        agreementHelper.reconcileBatch(ids);
    }

    // ==================== UpdateEscrow Edge Cases ====================

    function test_UpdateEscrow_FullThawWithdrawCycle() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Remove the agreement
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        // First reconcileCollectorProvider: initiates thaw
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Warp past mock's thawing period (1 day)
        vm.warp(block.timestamp + 1 days + 1);

        // Second reconcileCollectorProvider: withdraws thawed tokens, then no more to thaw
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Third reconcileCollectorProvider: should be a no-op (nothing to thaw or withdraw)
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
    }

    // ==================== Multiple Pending Update Replacements ====================

    // ==================== Zero-Value Pending Update Hash Cleanup ====================

    function test_OfferUpdate_ZeroValuePendingUpdate_HashCleanedOnReplace() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Offer a zero-value pending update (both initial and ongoing are 0)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            0, // zero initial
            0, // zero ongoing
            60,
            3600,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        bytes32 zeroHash = recurringCollector.hashRCAU(rcau1);
        // Zero-value hash should still be authorized
        assertEq(agreementManager.approveAgreement(zeroHash), IAgreementOwner.approveAgreement.selector);
        // sumMaxNextClaim should be unchanged (original + 0)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        // Replace with a non-zero update (same nonce — collector hasn't accepted either)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau2);

        // Old zero-value hash should be cleaned up
        assertEq(agreementManager.approveAgreement(zeroHash), bytes4(0));

        // New hash should be authorized
        bytes32 newHash = recurringCollector.hashRCAU(rcau2);
        assertEq(agreementManager.approveAgreement(newHash), IAgreementOwner.approveAgreement.selector);

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pendingMaxClaim);
    }

    function test_Reconcile_ZeroValuePendingUpdate_ClearedWhenApplied() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Offer a zero-value pending update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            0,
            0,
            60,
            3600,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau);

        bytes32 zeroHash = recurringCollector.hashRCAU(rcau);
        assertEq(agreementManager.approveAgreement(zeroHash), IAgreementOwner.approveAgreement.selector);

        // Simulate: agreement accepted with update applied (pending nonce <= updateNonce)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: uint64(block.timestamp),
                lastCollectionAt: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 0,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                updateNonce: 1,
                canceledAt: 0,
                state: IRecurringCollector.AgreementState.Accepted
            })
        );

        agreementManager.reconcileAgreement(agreementId);

        // Zero-value pending hash should be cleaned up
        assertEq(agreementManager.approveAgreement(zeroHash), bytes4(0));

        // Pending fields should be cleared
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(agreementId);
        assertEq(info.pendingUpdateMaxNextClaim, 0);
        assertEq(info.pendingUpdateNonce, 0);
        assertEq(info.pendingUpdateHash, bytes32(0));
    }

    // ==================== Re-offer After Remove ====================

    function test_ReofferAfterRemove_FullLifecycle() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        // 1. Offer
        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);

        // 2. SP cancels and remove
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);

        // 3. Re-offer the same agreement (same parameters, same agreementId)
        bytes16 reofferedId = _offerAgreement(rca);
        assertEq(reofferedId, agreementId);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);

        // 4. Verify the re-offered agreement is fully functional
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(reofferedId);
        assertTrue(info.provider != address(0));
        assertEq(info.provider, indexer);
        assertEq(info.maxNextClaim, maxClaim);

        // Hash is authorized again
        bytes32 rcaHash = recurringCollector.hashRCA(rca);
        assertEq(agreementManager.approveAgreement(rcaHash), IAgreementOwner.approveAgreement.selector);
    }

    function test_ReofferAfterRemove_WithDifferentNonce() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        bytes16 id1 = _offerAgreement(rca1);

        // Remove
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);

        // Re-offer with different nonce (different agreementId)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id2 = _offerAgreement(rca2);
        assertTrue(id1 != id2);

        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim2);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    // ==================== Input Validation ====================

    function test_Offer_Revert_ZeroServiceProvider() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.serviceProvider = address(0);

        token.mint(address(agreementManager), 1_000_000 ether);
        vm.expectRevert(IRecurringAgreementManagement.ServiceProviderZeroAddress.selector);
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    function test_Offer_Revert_ZeroDataService() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.dataService = address(0);

        token.mint(address(agreementManager), 1_000_000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringAgreementManagement.UnauthorizedDataService.selector, address(0))
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca, _collector());
    }

    // ==================== getProviderAgreements ====================

    function test_GetIndexerAgreements_Empty() public {
        bytes16[] memory ids = agreementManager.getProviderAgreements(indexer);
        assertEq(ids.length, 0);
    }

    function test_GetIndexerAgreements_SingleAgreement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        bytes16[] memory ids = agreementManager.getProviderAgreements(indexer);
        assertEq(ids.length, 1);
        assertEq(ids[0], agreementId);
    }

    function test_GetIndexerAgreements_MultipleAgreements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        bytes16[] memory ids = agreementManager.getProviderAgreements(indexer);
        assertEq(ids.length, 2);
        // EnumerableSet maintains insertion order
        assertEq(ids[0], id1);
        assertEq(ids[1], id2);
    }

    function test_GetIndexerAgreements_AfterRemoval() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        // Remove first agreement
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);

        bytes16[] memory ids = agreementManager.getProviderAgreements(indexer);
        assertEq(ids.length, 1);
        assertEq(ids[0], id2);
    }

    function test_GetIndexerAgreements_CrossIndexerIsolation() public {
        address indexer2 = makeAddr("indexer2");

        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        bytes16[] memory indexer1Ids = agreementManager.getProviderAgreements(indexer);
        bytes16[] memory indexer2Ids = agreementManager.getProviderAgreements(indexer2);

        assertEq(indexer1Ids.length, 1);
        assertEq(indexer1Ids[0], id1);
        assertEq(indexer2Ids.length, 1);
        assertEq(indexer2Ids[0], id2);
    }

    function test_GetIndexerAgreements_Paginated() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        // Full range returns both
        bytes16[] memory all = agreementManager.getProviderAgreements(indexer, 0, 10);
        assertEq(all.length, 2);
        assertEq(all[0], id1);
        assertEq(all[1], id2);

        // Offset skips first
        bytes16[] memory fromOne = agreementManager.getProviderAgreements(indexer, 1, 10);
        assertEq(fromOne.length, 1);
        assertEq(fromOne[0], id2);

        // Count limits result
        bytes16[] memory firstOnly = agreementManager.getProviderAgreements(indexer, 0, 1);
        assertEq(firstOnly.length, 1);
        assertEq(firstOnly[0], id1);
    }

    // ==================== Withdraw Timing Boundary (Issue 1) ====================

    function test_UpdateEscrow_NoWithdrawAtExactThawEnd() public {
        // At exactly thawEndTimestamp, PaymentsEscrow does NOT allow withdrawal
        // (real contract: `block.timestamp <= thawEnd` returns 0).
        // RecurringAgreementManager must not enter the withdraw branch at the boundary.
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // SP cancels — reconcile triggers thaw
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        IPaymentsEscrow.EscrowAccount memory accountBeforeWarp;
        (
            accountBeforeWarp.balance,
            accountBeforeWarp.tokensThawing,
            accountBeforeWarp.thawEndTimestamp
        ) = paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertEq(accountBeforeWarp.tokensThawing, maxClaim, "All tokens should be thawing");
        uint256 thawEnd = accountBeforeWarp.thawEndTimestamp;
        assertTrue(0 < thawEnd, "Thaw should be active");

        // Warp to EXACTLY thawEndTimestamp (boundary)
        vm.warp(thawEnd);

        // Record logs to verify no EscrowWithdrawn event
        vm.recordLogs();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 withdrawSig = keccak256("EscrowWithdrawn(address,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(
                entries[i].topics[0] != withdrawSig,
                "EscrowWithdrawn must not be emitted at exact thawEndTimestamp"
            );
        }

        // Escrow balance should be unchanged (still thawing)
        IPaymentsEscrow.EscrowAccount memory accountAfter;
        (accountAfter.balance, accountAfter.tokensThawing, accountAfter.thawEndTimestamp) = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertEq(accountAfter.balance, maxClaim, "Balance unchanged at boundary");
        assertEq(accountAfter.tokensThawing, maxClaim, "Still thawing at boundary");
    }

    function test_UpdateEscrow_WithdrawsOneSecondAfterThawEnd() public {
        // One second past thawEndTimestamp, withdrawal should succeed.
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        (, , uint256 thawEnd) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Warp to thawEndTimestamp + 1
        vm.warp(thawEnd + 1);

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.EscrowWithdrawn(indexer, address(recurringCollector), maxClaim);

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Escrow should be empty
        (uint256 finalBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(finalBalance, 0);
    }

    // ==================== BeforeCollection Boundary (Issue 2) ====================

    function test_BeforeCollection_NoOpWhenTokensToCollectEqualsBalance() public {
        // When tokensToCollect == escrow balance, beforeCollection should be a no-op.
        // Bug: current code uses strict '<', falling through when equal.
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertTrue(0 < escrowBalance, "Escrow should be funded");

        // Drain manager's free token balance
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }
        assertEq(token.balanceOf(address(agreementManager)), 0, "Manager has no free tokens");

        // Request exactly the escrow balance — no deficit exists
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, escrowBalance);

        // No deficit — collection should succeed without issue
    }

    // ==================== Cancel Event Behavior ====================

    function test_CancelAgreement_NoEvent_WhenAlreadyCanceled() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Set as already CanceledByServiceProvider
        _setAgreementCanceledBySP(agreementId, rca);

        // Record logs to verify no AgreementCanceled event
        vm.recordLogs();
        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);

        // Check that no AgreementCanceled event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 cancelEventSig = keccak256("AgreementCanceled(bytes16,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(
                entries[i].topics[0] != cancelEventSig,
                "AgreementCanceled should not be emitted on idempotent path"
            );
        }
    }

    function test_CancelAgreement_EmitsEvent_WhenAccepted() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementCanceled(agreementId, indexer);

        vm.prank(operator);
        agreementManager.cancelAgreement(agreementId);
    }

    // ==================== Multiple Pending Update Replacements ====================

    function test_OfferUpdate_ThreeConsecutiveReplacements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Update 1
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            1
        );
        _offerAgreementUpdate(rcau1);
        uint256 pending1 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pending1);

        // Update 2 replaces 1 (same nonce — collector hasn't accepted either)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            1
        );
        _offerAgreementUpdate(rcau2);
        uint256 pending2 = 0.5 ether * 1800 + 50 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pending2);

        // Update 3 replaces 2 (same nonce — collector still hasn't accepted)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau3 = _makeRCAU(
            agreementId,
            300 ether,
            3 ether,
            60,
            3600,
            uint64(block.timestamp + 1095 days),
            1
        );
        _offerAgreementUpdate(rcau3);
        uint256 pending3 = 3 ether * 3600 + 300 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim + pending3);

        // Only hash for update 3 should be authorized
        bytes32 hash1 = recurringCollector.hashRCAU(rcau1);
        bytes32 hash2 = recurringCollector.hashRCAU(rcau2);
        bytes32 hash3 = recurringCollector.hashRCAU(rcau3);

        assertEq(agreementManager.approveAgreement(hash1), bytes4(0));
        assertEq(agreementManager.approveAgreement(hash2), bytes4(0));
        assertEq(agreementManager.approveAgreement(hash3), IAgreementOwner.approveAgreement.selector);
    }
}
