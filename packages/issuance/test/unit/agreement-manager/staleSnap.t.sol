// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

/// @notice PoC: stale escrowSnap in _escrowMinMax causes afterCollection to revert,
/// which is silently swallowed by RecurringCollector's try/catch, leaving the snap
/// permanently stale. Manual recovery via reconcileAgreement also reverts.

contract StaleEscrowSnapTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    address internal indexer2;

    // Agreement parameters: maxNextClaim = 1 ether * 3600 + 100 ether = 3700 ether
    uint256 constant MAX_INITIAL = 100 ether;
    uint256 constant MAX_ONGOING = 1 ether;
    uint32 constant MAX_SEC = 3600;
    uint256 constant MAX_NEXT_CLAIM = MAX_ONGOING * MAX_SEC + MAX_INITIAL; // 3700 ether

    function setUp() public override {
        super.setUp();
        indexer2 = makeAddr("indexer2");
    }

    /// @notice Helper: create an RCA for a specific provider with a specific nonce
    function _makeRCAFor(
        address provider,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = IRecurringCollector.RecurringCollectionAgreement({
            deadline: uint64(block.timestamp + 1 hours),
            endsAt: uint64(block.timestamp + 365 days),
            payer: address(agreementManager),
            dataService: dataService,
            serviceProvider: provider,
            maxInitialTokens: MAX_INITIAL,
            maxOngoingTokensPerSecond: MAX_ONGOING,
            minSecondsPerCollection: 60,
            maxSecondsPerCollection: MAX_SEC,
            nonce: nonce,
            metadata: ""
        });
        agreementId = recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
    }

    /// @notice Helper: offer an agreement and fund just enough for Full mode deposit,
    /// leaving the RAM with a tiny free balance (DUST) afterward.
    uint256 constant DUST = 1 ether;

    function _offerWithTightBalance(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        // Mint maxNextClaim + dust so strict < check passes in _escrowMinMax:
        //   totalEscrowDeficit (3700) < balanceOf (3701) → true → Full mode
        // After deposit of 3700 into escrow, RAM keeps DUST.
        token.mint(address(agreementManager), MAX_NEXT_CLAIM + DUST);
        vm.prank(operator);
        return agreementManager.offerAgreement(rca, _collector());
    }

    /// @notice Helper: simulate a collection by directly draining escrow and updating
    /// the collector's agreement state (as would happen in a real collection)
    function _simulateCollection(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        address provider,
        uint256 drainAmount,
        uint64 acceptedAt,
        uint64 lastCollectionAt
    ) internal {
        // Drain escrow balance (simulates PaymentsEscrow.collect called by RecurringCollector)
        (uint256 balBefore, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            provider
        );
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            provider,
            balBefore - drainAmount, // reduced balance
            0, // no thawing
            0 // no thaw timestamp
        );

        // Update collector state (lastCollectionAt advances, reducing maxNextClaim)
        recurringCollector.setAgreement(
            agreementId,
            IRecurringCollector.AgreementData({
                dataService: rca.dataService,
                payer: rca.payer,
                serviceProvider: rca.serviceProvider,
                acceptedAt: acceptedAt,
                lastCollectionAt: lastCollectionAt,
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
    }

    // =========================================================================
    // Test 1: afterCollection reverts when escrow is drained and RAM is underfunded
    // =========================================================================

    function test_AfterCollection_RevertsWhenEscrowDrainedAndRAMUnderfunded() public {
        // --- Setup: offer agreement, accept it, fund escrow exactly ---
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAFor(indexer, 1);
        bytes16 id = _offerWithTightBalance(rca);
        assertEq(id, agreementId);

        // Verify escrow is fully funded, RAM has only dust remaining
        (uint256 escrowBal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBal, MAX_NEXT_CLAIM, "escrow should be fully funded");
        assertEq(token.balanceOf(address(agreementManager)), DUST, "RAM should have only dust");

        // Mark agreement as accepted on the collector
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        // Advance time so collection is valid
        vm.warp(block.timestamp + 1 hours);

        // --- Simulate collection draining most of the escrow ---
        uint256 drainAmount = 3000 ether;
        _simulateCollection(
            agreementId,
            rca,
            indexer,
            drainAmount,
            uint64(block.timestamp - 1 hours), // acceptedAt
            uint64(block.timestamp) // lastCollectionAt = now
        );

        // Verify state: escrow drained, RAM has only dust
        (escrowBal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(escrowBal, MAX_NEXT_CLAIM - drainAmount, "escrow drained by collection");
        assertEq(token.balanceOf(address(agreementManager)), DUST, "RAM has only dust remaining");

        // Snapshot BEFORE afterCollection
        uint256 snapBefore = _getEscrowSnap(indexer);
        assertEq(snapBefore, MAX_NEXT_CLAIM, "snap is stale (pre-collection value)");

        // --- afterCollection reverts internally ---
        // _reconcileAgreement will reduce sumMaxNextClaim, but the snap is stale-high
        // so _escrowMinMax sees totalEscrowDeficit=0, keeps Full mode, tries to deposit
        // to bring escrow back to the new sumMaxNextClaim — but RAM has 0 balance.
        // The deposit reverts, which propagates up through afterCollection.
        vm.prank(address(recurringCollector));
        vm.expectRevert(); // ERC20 transfer reverts (insufficient balance)
        agreementManager.afterCollection(agreementId, drainAmount);

        // Snap is STILL stale because afterCollection reverted
        uint256 snapAfter = _getEscrowSnap(indexer);
        assertEq(snapAfter, snapBefore, "snap unchanged - afterCollection reverted before _setEscrowSnap");
    }

    // =========================================================================
    // Test 2: self-reinforcing — subsequent afterCollection also reverts
    // =========================================================================

    function test_SelfReinforcing_SubsequentAfterCollectionAlsoReverts() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAFor(indexer, 1);
        _offerWithTightBalance(rca);
        uint64 t0 = uint64(block.timestamp);
        _setAgreementAccepted(agreementId, rca, t0);

        // --- First collection at t0 + 1h ---
        vm.warp(t0 + 1 hours);
        _simulateCollection(agreementId, rca, indexer, 3000 ether, t0, uint64(block.timestamp));

        vm.prank(address(recurringCollector));
        vm.expectRevert();
        agreementManager.afterCollection(agreementId, 3000 ether);

        // --- Second collection at t0 + 2h ---
        vm.warp(t0 + 2 hours);
        // Escrow is at 700 after first drain; drain another 200 → 500
        _simulateCollection(agreementId, rca, indexer, 200 ether, t0, uint64(block.timestamp));

        vm.prank(address(recurringCollector));
        vm.expectRevert();
        agreementManager.afterCollection(agreementId, 200 ether);

        // Snap is STILL the original value from offer time — permanently stale
        uint256 snap = _getEscrowSnap(indexer);
        assertEq(snap, MAX_NEXT_CLAIM, "snap permanently stale across multiple collections");
    }

    // =========================================================================
    // Test 3: manual reconcileAgreement also reverts (no recovery path)
    // =========================================================================

    function test_ManualReconcile_AlsoReverts() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeRCAFor(indexer, 1);
        _offerWithTightBalance(rca);
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));

        vm.warp(block.timestamp + 1 hours);

        // Collection drains escrow
        _simulateCollection(
            agreementId,
            rca,
            indexer,
            3000 ether,
            uint64(block.timestamp - 1 hours),
            uint64(block.timestamp)
        );

        // afterCollection reverts (as shown above)
        vm.prank(address(recurringCollector));
        vm.expectRevert();
        agreementManager.afterCollection(agreementId, 3000 ether);

        // Try manual recovery via reconcileAgreement — ALSO reverts
        // Same code path: _reconcileAndCleanup -> _reconcileAndUpdateEscrow -> _updateEscrow
        // Same stale snap -> same deposit attempt -> same revert
        vm.expectRevert();
        agreementManager.reconcileAgreement(agreementId);

        // reconcileCollectorProvider also reverts (same _updateEscrow path)
        vm.expectRevert();
        agreementManager.reconcileCollectorProvider(address(recurringCollector), indexer);
    }

    // =========================================================================
    // Helper: read escrowSnap via the only observable proxy (totalEscrowDeficit)
    // Since escrowSnap is internal storage, we infer it from the escrow balance
    // returned by getEscrowAccount vs the deficit accounting.
    // =========================================================================

    /// @notice Get the effective escrow snap for a provider by computing what
    /// the RAM thinks the balance is based on its deficit accounting.
    /// escrowSnap = sumMaxNextClaim - providerDeficit
    /// providerDeficit = totalEscrowDeficit (when only one pair exists)
    function _getEscrowSnap(address provider) internal view returns (uint256) {
        uint256 sumMax = agreementManager.getSumMaxNextClaim(_collector(), provider);
        uint256 totalDeficit = agreementManager.getTotalEscrowDeficit();
        // With one pair, totalEscrowDeficit == providerDeficit
        // providerDeficit = max(0, sumMaxNextClaim - escrowSnap)
        // So escrowSnap = sumMaxNextClaim - providerDeficit (when deficit <= sumMax)
        if (totalDeficit > sumMax) return 0;
        return sumMax - totalDeficit;
    }

    /* solhint-enable graph/func-name-mixedcase */
}
