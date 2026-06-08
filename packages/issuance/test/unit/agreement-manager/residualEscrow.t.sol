// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

/// @notice Tests for minResidualEscrowFactor — residual escrow threshold for pair cleanup.
contract RecurringAgreementManagerResidualEscrowTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // -- Helpers --

    /// @notice Create an agreement, cancel it, and advance past the thaw period so escrow is withdrawable.
    function _createAndCancelAgreement()
        private
        returns (bytes16 agreementId, IRecurringCollector.RecurringCollectionAgreement memory rca)
    {
        (rca, ) = _makeRCAWithId(100 ether, 1 ether, 3600, uint64(block.timestamp + 365 days));
        agreementId = _offerAgreement(rca);

        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
    }

    /// @notice Inject dust directly into escrow (simulates external depositTo by attacker).
    function _injectDust(uint256 amount) private {
        (uint256 bal, uint256 thawing, uint256 thawEnd) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // Mint backing tokens to the escrow so withdraw can transfer them
        token.mint(address(paymentsEscrow), amount);
        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            bal + amount,
            thawing,
            thawEnd
        );
    }

    // -- Tests: residual threshold drops tracking --

    function test_ResidualEscrow_DropsTrackingBelowThreshold() public {
        // Default factor = 50, threshold = 2^50 ≈ 1.1e15
        _createAndCancelAgreement();

        // Advance past thaw period so escrow can be withdrawn
        vm.warp(block.timestamp + 1 days + 1);

        // reconcileProvider: withdraws full balance, dust is zero, pair is dropped
        bool tracked = agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertFalse(tracked, "pair should be dropped when escrow is zero");
        assertEq(
            agreementManager.getProviderCount(IAgreementCollector(address(recurringCollector))),
            0,
            "provider should be removed from set"
        );
        assertEq(agreementManager.getCollectorCount(), 0, "collector should be removed from set");
    }

    function test_ResidualEscrow_KeepsTrackingAboveThreshold() public {
        _createAndCancelAgreement();

        // Inject balance well above threshold (2^50 ≈ 1.1e15)
        vm.warp(block.timestamp + 1 days + 1);
        _injectDust(1 ether);

        bool tracked = agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertTrue(tracked, "pair should remain tracked when escrow exceeds threshold");
    }

    function test_ResidualEscrow_DustGriefingDropsTracking() public {
        _createAndCancelAgreement();

        // Advance past thaw, then inject 1 wei (simulates attacker depositTo)
        vm.warp(block.timestamp + 1 days + 1);
        _injectDust(1);

        // reconcileProvider: withdraws matured thaw, 1 wei remains,
        // 1 wei < 2^50 threshold → pair is dropped
        bool tracked = agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertFalse(tracked, "dust should not prevent cleanup");
    }

    // -- Tests: blind drain for untracked pairs --

    function test_ResidualEscrow_BlindDrainUntrackedPair() public {
        _createAndCancelAgreement();

        // Drop tracking first
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(agreementManager.getProviderCount(IAgreementCollector(address(recurringCollector))), 0);

        // Inject dust into the now-untracked escrow
        _injectDust(100);

        // reconcileProvider on untracked pair: blind drain starts thaw
        bool tracked = agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertFalse(tracked, "untracked pair should stay untracked");

        // Escrow should now be thawing
        (uint256 bal, uint256 thawing, ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(thawing, bal, "full balance should be thawing");
    }

    function test_ResidualEscrow_BlindDrainWithdrawsMaturedThaw() public {
        _createAndCancelAgreement();

        // Drop tracking
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Inject dust, start thaw via blind drain
        _injectDust(100);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Read the thaw end timestamp and advance past it
        (, , uint256 thawEnd) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        vm.warp(thawEnd + 1);

        uint256 balBefore = token.balanceOf(address(agreementManager));
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        uint256 balAfter = token.balanceOf(address(agreementManager));

        assertEq(balAfter - balBefore, 100, "dust should be withdrawn to agreement manager");
    }

    function test_ResidualEscrow_BlindDrainNoopMidThaw() public {
        _createAndCancelAgreement();

        // Drop tracking
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Inject dust, start thaw
        _injectDust(100);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Inject more dust mid-thaw — blind drain should NOT reset the timer
        _injectDust(50);

        (, , uint256 thawEndBefore) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        (, uint256 thawingAfter, uint256 thawEndAfter) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Timer should not have reset (evenIfTimerReset=false)
        assertEq(thawEndAfter, thawEndBefore, "thaw timer should not reset on blind drain mid-thaw");
        // Only the original 100 should be thawing, not 150
        assertEq(thawingAfter, 100, "thaw amount should not increase mid-thaw");
    }

    // -- Tests: re-entry after drop restores tracking --

    function test_ResidualEscrow_ReentryRestoresTracking() public {
        _createAndCancelAgreement();

        // Drop tracking
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertEq(agreementManager.getCollectorCount(), 0, "collector should be removed");

        // New agreement for the same (collector, provider) pair
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        _offerAgreement(rca2);

        // Tracking should be restored
        assertEq(
            agreementManager.getProviderCount(IAgreementCollector(address(recurringCollector))),
            1,
            "provider should be re-tracked"
        );
        assertEq(agreementManager.getCollectorCount(), 1, "collector should be re-tracked");
    }

    function test_ResidualEscrow_ReentryWithStaleSnapCorrects() public {
        _createAndCancelAgreement();

        // Inject extra balance, then drop tracking — snap records the inflated balance
        _injectDust(500);
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // Escrow still has some balance (the dust that was below threshold or leftover)
        // Now create new agreement — snap should be corrected from real balance
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        _offerAgreement(rca2);

        // The system should work normally — no stale snap causing issues
        // Verify escrow is funded correctly for the new agreement
        (uint256 bal, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 expectedMaxClaim = 0.5 ether * 3600 + 50 ether;
        assertEq(bal, expectedMaxClaim, "escrow should be funded for new agreement (snap corrected)");
    }

    // -- Tests: setter --

    function test_ResidualEscrow_SetFactor() public {
        assertEq(agreementManager.getMinResidualEscrowFactor(), 50, "default should be 50");

        vm.prank(operator);
        agreementManager.setMinResidualEscrowFactor(60);
        assertEq(agreementManager.getMinResidualEscrowFactor(), 60);
    }

    function test_ResidualEscrow_SetFactor_SameValueNoop() public {
        vm.prank(operator);
        // Should not emit event
        vm.recordLogs();
        agreementManager.setMinResidualEscrowFactor(50);
        assertEq(vm.getRecordedLogs().length, 0, "no event on same value");
    }

    function test_ResidualEscrow_SetFactor_EmitsEvent() public {
        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.MinResidualEscrowFactorSet(50, 100);

        vm.prank(operator);
        agreementManager.setMinResidualEscrowFactor(100);
    }

    function test_ResidualEscrow_SetFactor_ZeroDisables() public {
        _createAndCancelAgreement();

        vm.prank(operator);
        agreementManager.setMinResidualEscrowFactor(0);

        // With factor=0, threshold = 2^0 = 1, only drops at zero balance
        // Inject 1 wei — should keep tracking
        vm.warp(block.timestamp + 1 days + 1);
        _injectDust(1);

        bool tracked = agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);
        assertTrue(tracked, "factor=0 means threshold=1, 1 wei should keep tracking");
    }
}
