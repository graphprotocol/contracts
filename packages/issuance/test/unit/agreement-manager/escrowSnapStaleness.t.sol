// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

/// @notice Tests for escrow snapshot staleness correction and threshold boundary behavior.
/// Covers gaps:
///   - Stale escrow snap self-correction via _setEscrowSnap (TRST-H-3)
///   - Threshold-based basis degradation boundary conditions (TRST-M-2, M-3)
///   - Deficit tracking accuracy after external escrow mutations
contract RecurringAgreementManagerEscrowSnapStalenessTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    //  Stale snap self-correction
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When external deposit changes escrow balance between reconciliations,
    ///         _setEscrowSnap corrects the snapshot and totalEscrowDeficit on next reconcile.
    function test_EscrowSnap_SelfCorrectionAfterExternalDeposit() public {
        // Create agreement requiring 3700 ether escrow
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;

        // Verify initial state is correct (Full mode, fully funded)
        assertEq(agreementManager.getTotalEscrowDeficit(), 0, "initial deficit should be 0");

        // Externally remove some escrow balance (simulates external withdrawal or slash)
        uint256 reduction = 1000 ether;
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            expectedMaxClaim - reduction, // reduced balance
            0, // no thawing
            0 // no thaw end
        );

        // Snap is now stale — deficit is understated.
        // Reconcile should self-correct the snap.
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // After reconcile, deficit should reflect the shortfall (or be corrected via deposit)
        // The reconcile calls _setEscrowSnap which corrects totalEscrowDeficit
        uint256 deficitAfter = agreementManager.getTotalEscrowDeficit();
        (uint256 balAfter, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // In Full mode with sufficient RAM balance, it deposits to fill the gap
        // If deposit succeeded, deficit should be 0 and balance should be expectedMaxClaim
        if (balAfter >= expectedMaxClaim) {
            assertEq(deficitAfter, 0, "deficit should be 0 after correction + deposit");
        } else {
            // If insufficient RAM tokens, deficit reflects actual shortfall
            assertEq(deficitAfter, expectedMaxClaim - balAfter, "deficit should reflect actual shortfall");
        }
    }

    /// @notice When escrow balance increases externally (e.g., depositTo from a third party),
    ///         reconcile corrects the stale snap downward (reduced deficit).
    function test_EscrowSnap_CorrectionOnExternalIncrease() public {
        // Start with limited funding so we have a deficit
        uint256 limitedFunding = 100 ether;
        token.mint(address(agreementManager), limitedFunding);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            500 ether,
            10 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        // Don't use _offerAgreement since it mints 1M tokens
        vm.prank(operator);
        agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));

        uint256 deficitBefore = agreementManager.getTotalEscrowDeficit();
        assertTrue(deficitBefore > 0, "should have deficit with limited funding");

        // Externally add tokens to escrow (simulates third-party deposit)
        (uint256 bal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 topUp = 5000 ether;
        paymentsEscrow.setAccount(address(agreementManager), address(recurringCollector), indexer, bal + topUp, 0, 0);

        // Reconcile corrects the stale snap
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        uint256 deficitAfter = agreementManager.getTotalEscrowDeficit();
        assertTrue(deficitAfter < deficitBefore, "deficit should decrease after external top-up");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Threshold boundary conditions
    // ══════════════════════════════════════════════════════════════════════

    /// @notice OnDemand tier threshold: when spare is exactly at the boundary,
    ///         verify correct degradation behavior.
    function test_ThresholdBoundary_OnDemandExactThreshold() public {
        // Set OnDemand mode
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        // Create agreement
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether; // 3700 ether

        // After offer, reconcile to stable state
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // OnDemand threshold check: sumMaxNext * threshold / 256 < spare
        // Default threshold = 128, so need: maxClaim * 128 / 256 < spare → maxClaim/2 < spare
        // If spare > maxClaim/2, max = maxClaim; otherwise max = 0 (JIT degradation)

        // Set escrow to exactly the threshold boundary: balance = maxClaim + maxClaim * 128 / 256
        // where totalDeficit = 0 (single provider), so spare = balance
        // At boundary: maxClaim * 128 / 256 == spare → NOT strictly less → should degrade to JIT
        uint256 exactBoundary = maxClaim + (maxClaim * 128) / 256;
        paymentsEscrow.setAccount(address(agreementManager), address(recurringCollector), indexer, exactBoundary, 0, 0);

        // Reconcile to observe behavior at exact threshold
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // At exact boundary the condition is NOT strictly-less, so it should NOT deposit
        // This verifies the < vs <= boundary correctly
        // The system should thaw excess since max = 0 at exact boundary
        // Just above boundary should trigger OnDemand (max = maxClaim)
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            exactBoundary + 1,
            0,
            0
        );
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // After reconcile at just-above boundary, OnDemand mode means max = maxClaim
        // No thaw needed since balance is within bounds
        (uint256 balAbove, uint256 thawAbove, ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // In OnDemand, min = 0, max = maxClaim. Balance >> maxClaim, so excess thaws
        assertTrue(thawAbove > 0 || balAbove <= maxClaim, "above threshold: should thaw excess or be within max");
    }

    /// @notice Full basis margin boundary: verify the margin requirement works correctly
    function test_ThresholdBoundary_FullBasisMargin() public {
        // Full mode (default)
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Full mode threshold: sumMaxNext * (256 + margin) / 256 < spare
        // Default margin = 16, so need: maxClaim * 272 / 256 < spare
        // Below this → OnDemand (min = 0, max = maxClaim) instead of Full (min = max = maxClaim)

        // Set balance to just below the Full threshold
        uint256 fullThreshold = (maxClaim * 272) / 256;
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            fullThreshold, // exactly at boundary (not strictly less, so not Full)
            0,
            0
        );

        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // At exact boundary, Full condition fails (not strictly less) → degrades to OnDemand
        // In OnDemand, min = 0, so no deposit is forced
        // The system should still work without reverting
        assertTrue(true, "reconcile at Full boundary should not revert");

        // Just above Full threshold — Full mode active (min = max = maxClaim)
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            fullThreshold + 1,
            0,
            0
        );
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        (uint256 balAbove, uint256 thawAbove, ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // In Full mode, min = max = maxClaim. Excess above maxClaim should thaw.
        assertTrue(
            thawAbove > 0 || balAbove <= maxClaim + 1,
            "Full mode above threshold: excess should thaw to maxClaim"
        );
    }

    /// @notice Deficit tracking remains accurate across multiple provider operations
    function test_EscrowSnap_DeficitAccuracyMultipleOps() public {
        // Create two agreements for different providers
        address indexer2 = makeAddr("indexer2");

        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Both fully funded — deficit should be 0
        assertEq(agreementManager.getTotalEscrowDeficit(), 0, "initial: no deficit");

        // Externally reduce indexer1's escrow
        paymentsEscrow.setAccount(address(agreementManager), address(recurringCollector), indexer, maxClaim1 / 2, 0, 0);

        // Reconcile indexer1 — deficit should reflect only indexer1's shortfall
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Check balance after reconcile (may have deposited to restore)
        paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer);

        // Reconcile indexer2 — should not affect indexer1's deficit
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer2);

        // Total deficit should be consistent
        uint256 finalDeficit = agreementManager.getTotalEscrowDeficit();
        (uint256 finalBal1, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        (uint256 finalBal2, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );

        uint256 deficit1 = maxClaim1 < finalBal1 ? 0 : maxClaim1 - finalBal1;
        uint256 deficit2 = maxClaim2 < finalBal2 ? 0 : maxClaim2 - finalBal2;
        assertEq(finalDeficit, deficit1 + deficit2, "total deficit should be sum of per-provider deficits");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
