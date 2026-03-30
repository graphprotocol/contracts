// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { Vm } from "forge-std/Vm.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import {
    REGISTERED,
    ACCEPTED,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { MockRecurringCollector } from "./mocks/MockRecurringCollector.sol";

/// @notice Edge case and boundary condition tests for RecurringAgreementManager.
contract RecurringAgreementManagerEdgeCasesTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Helpers --

    function _getProviderAgreements(address provider) internal view returns (bytes16[] memory result) {
        uint256 count = agreementManager.getAgreementCount(
            IAgreementCollector(address(recurringCollector)),
            provider
        );
        result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i)
            result[i] = agreementManager.getAgreementAt(
                IAgreementCollector(address(recurringCollector)),
                provider,
                i
            );
    }

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

    // NOTE: test_CancelAgreement_Revert_WhenDataServiceHasNoCode removed —
    // cancelAgreement now calls collector.cancel() directly, no data service interaction.

    // ==================== Hash Cleanup Tests ====================

    function test_CancelOffered_CleansUpAgreement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Agreement is tracked
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        _cancelAgreement(agreementId);

        // Agreement is cleaned up
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_CancelOffered_CleansUpPendingUpdate() public {
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

        _cancelAgreement(agreementId);

        // Agreement and pending update fully cleaned up
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_Remove_CleansUpAgreement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels — removable
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Agreement is fully cleaned up
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_Remove_CleansUpPendingUpdate() public {
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

        // SP cancels — removable
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // Agreement and pending update fully cleaned up
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    function test_Reconcile_ClearsAppliedPendingUpdate() public {
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

        // Pending update is tracked on the collector

        // Simulate: agreement accepted with update applied (pending terms cleared on collector)
        IRecurringCollector.RecurringCollectionAgreement memory updatedRca = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days)
        );
        updatedRca.payer = rca.payer;
        updatedRca.dataService = rca.dataService;
        updatedRca.serviceProvider = rca.serviceProvider;
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            updatedRca,
            REGISTERED | ACCEPTED,
            uint64(block.timestamp),
            0,
            0
        );
        data.updateNonce = 1;
        recurringCollector.setAgreement(agreementId, data);

        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // After reconcile, maxNextClaim is recalculated from the new active terms
        IRecurringAgreements.AgreementInfo memory infoAfter = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        // maxNextClaim = 2e18 * 7200 + 200e18 = 14600e18
        assertEq(infoAfter.maxNextClaim, 14600 ether);
    }

    function test_OfferUpdate_ReplacesExistingPendingOnCollector() public {
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

        // max(current=3700, pending=14600) = 14600
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 14600 ether);

        // Cancel pending update clears pending terms on the collector — sum drops to active-only
        _cancelPendingUpdate(agreementId);

        // Sum drops to active-only (3700) since pending was cleared
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        // Collector's updateNonce is still 1, so next valid nonce is 2.
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            2
        );
        _offerAgreementUpdate(rcau2);

        // max(current=3700, pending=950) = 3700 (current dominates)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 3700 ether);
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
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            expectedMaxClaim
        );
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
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            100 ether
        );
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

        // maxNextClaim = 0 * 0 + 0 = 0 — immediately cleaned up
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
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
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertTrue(exists);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
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

        // Now removable (deadline < block.timestamp → getMaxNextClaim returns 0)
        bool exists = agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertFalse(exists);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);
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
        _setAgreementCollected(agreementId, rca, now_, rca.endsAt);

        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // getMaxNextClaim returns 0 when collectionEnd <= collectionStart
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            0
        );
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
    }

    // ==================== Cancel Edge Cases ====================

    // NOTE: test_CancelAgreement_Revert_WhenDataServiceReverts removed —
    // cancelAgreement now calls collector.cancel() directly, no data service interaction.

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
        bytes16 agreementId = agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Agreement is tracked even though escrow couldn't be funded
        assertEq(
            agreementManager.getAgreementMaxNextClaim(IAgreementCollector(address(recurringCollector)), agreementId),
            maxClaim
        );
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
        for (uint256 i = 0; i < ids.length; ++i)
            agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), ids[i]);

        // All reconciled to 0
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), 0);
    }

    function test_ReconcileBatch_EmptyArray() public {
        // Empty batch should succeed with no effect
        bytes16[] memory ids = new bytes16[](0);
        for (uint256 i = 0; i < ids.length; ++i)
            agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), ids[i]);
    }

    function test_ReconcileBatch_NonExistentAgreements() public {
        // Batch with non-existent IDs should skip silently
        bytes16[] memory ids = new bytes16[](2);
        ids[0] = bytes16(keccak256("nonexistent1"));
        ids[1] = bytes16(keccak256("nonexistent2"));

        for (uint256 i = 0; i < ids.length; ++i)
            agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), ids[i]);
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // First reconcileProvider: initiates thaw
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        // Warp past mock's thawing period (1 day)
        vm.warp(block.timestamp + 1 days + 1);

        // Second reconcileProvider: withdraws thawed tokens, then no more to thaw
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

        // Third reconcileProvider: should be a no-op (nothing to thaw or withdraw)
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);
    }

    // ==================== Multiple Pending Update Replacements ====================

    // ==================== Zero-Value Pending Update Hash Cleanup ====================

    function test_OfferUpdate_ZeroValuePendingUpdate_ReplacedByNonZero() public {
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

        // sumMaxNextClaim should be unchanged (original + 0)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        // Cancel pending update and replace with a non-zero update
        _cancelPendingUpdate(agreementId);

        // Collector's updateNonce is now 1, so next nonce must be 2
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 730 days),
            2
        );
        _offerAgreementUpdate(rcau2);

        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pendingMaxClaim = 14600 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pendingMaxClaim);
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

        // Simulate: agreement accepted with update applied (pending terms cleared on collector)
        IRecurringCollector.RecurringCollectionAgreement memory updatedRca = _makeRCA(
            0,
            0,
            60,
            3600,
            uint64(block.timestamp + 730 days)
        );
        updatedRca.payer = rca.payer;
        updatedRca.dataService = rca.dataService;
        updatedRca.serviceProvider = rca.serviceProvider;
        MockRecurringCollector.AgreementStorage memory data = _buildAgreementStorage(
            updatedRca,
            REGISTERED | ACCEPTED,
            uint64(block.timestamp),
            0,
            0
        );
        data.updateNonce = 1;
        recurringCollector.setAgreement(agreementId, data);

        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        // maxNextClaim should reflect the new (zero-value) active terms
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            agreementId
        );
        assertEq(info.maxNextClaim, 0);
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
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        // 2. SP cancels and remove
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 0);

        // 3. Re-offer the same agreement (same parameters, same agreementId)
        bytes16 reofferedId = _offerAgreement(rca);
        assertEq(reofferedId, agreementId);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        // 4. Verify the re-offered agreement is fully functional
        IRecurringAgreements.AgreementInfo memory info = agreementManager.getAgreementInfo(
            IAgreementCollector(address(recurringCollector)),
            reofferedId
        );
        assertTrue(info.provider != address(0));
        assertEq(info.provider, indexer);
        assertEq(info.maxNextClaim, maxClaim);
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);

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
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
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
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
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
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ==================== getProviderAgreements ====================

    function test_GetIndexerAgreements_Empty() public {
        bytes16[] memory ids = _getProviderAgreements(indexer);
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

        bytes16[] memory ids = _getProviderAgreements(indexer);
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

        bytes16[] memory ids = _getProviderAgreements(indexer);
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), id1);

        bytes16[] memory ids = _getProviderAgreements(indexer);
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

        bytes16[] memory indexer1Ids = _getProviderAgreements(indexer);
        bytes16[] memory indexer2Ids = _getProviderAgreements(indexer2);

        assertEq(indexer1Ids.length, 1);
        assertEq(indexer1Ids[0], id1);
        assertEq(indexer2Ids.length, 1);
        assertEq(indexer2Ids[0], id2);
    }

    function test_GetIndexerAgreements_Enumeration() public {
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

        // Count returns total
        assertEq(agreementManager.getAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 2);

        // Individual access by index
        assertEq(
            agreementManager.getAgreementAt(IAgreementCollector(address(recurringCollector)), indexer, 0),
            id1
        );
        assertEq(
            agreementManager.getAgreementAt(IAgreementCollector(address(recurringCollector)), indexer, 1),
            id2
        );
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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

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
        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

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
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);

        (, , uint256 thawEnd) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Warp to thawEndTimestamp + 1
        vm.warp(thawEnd + 1);

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.EscrowWithdrawn(indexer, address(recurringCollector), maxClaim);

        agreementManager.reconcileProvider(IAgreementCollector(address(_collector())), indexer);

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

    function test_CancelAgreement_AlreadyCanceled_StillForwards() public {
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

        // cancelAgreement always forwards to collector — no idempotent skip
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
        // Verify it doesn't revert — collector handles already-canceled state
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

        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        // cancelAgreement triggers the callback which reconciles — expect AgreementRemoved
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManagement.AgreementRemoved(agreementId);

        vm.prank(operator);
        agreementManager.cancelAgreement(IAgreementCollector(address(recurringCollector)), agreementId, activeHash, 0);
    }

    // ==================== Multiple Pending Update Replacements ====================

    function test_OfferUpdate_ThreeConsecutiveUpdates() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 originalMaxClaim = 1 ether * 3600 + 100 ether;

        // Update 1 (nonce=1)
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
        // max(current, pending) = max(3700, 14600) = 14600
        uint256 pending1 = 14600 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pending1);

        // Cancel pending update clears pending on collector, sum drops to active-only
        _cancelPendingUpdate(agreementId);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = _makeRCAU(
            agreementId,
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days),
            2
        );
        _offerAgreementUpdate(rcau2);
        // max(current, pending) = max(3700, 950) = 3700 (current dominates)
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), originalMaxClaim);

        // Cancel pending update 2 and offer update 3 (nonce=3)
        _cancelPendingUpdate(agreementId);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau3 = _makeRCAU(
            agreementId,
            300 ether,
            3 ether,
            60,
            3600,
            uint64(block.timestamp + 1095 days),
            3
        );
        _offerAgreementUpdate(rcau3);
        // max(current, pending) = max(3700, 11100) = 11100
        uint256 pending3 = 11100 ether;
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), pending3);
    }
}
