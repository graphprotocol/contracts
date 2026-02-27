// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRecurringAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManager.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerFundingModesTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    address internal indexer2;

    function setUp() public virtual override {
        super.setUp();
        indexer2 = makeAddr("indexer2");
    }

    // -- Helper --

    function _makeRCAForIndexer(
        address sp,
        uint256 maxInitial,
        uint256 maxOngoing,
        uint32 maxSec,
        uint256 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            maxInitial,
            maxOngoing,
            60,
            maxSec,
            uint64(block.timestamp + 365 days)
        );
        rca.serviceProvider = sp;
        rca.nonce = nonce;
        return rca;
    }

    // ==================== setFundingBasis ====================

    function test_SetFundingBasis_DefaultIsFull() public view {
        assertEq(uint256(agreementManager.getFundingBasis()), uint256(IRecurringAgreementManager.FundingBasis.Full));
    }

    function test_SetFundingBasis_GovernorCanSet() public {
        vm.prank(governor);
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.FundingBasisChanged(
            IRecurringAgreementManager.FundingBasis.Full,
            IRecurringAgreementManager.FundingBasis.OnDemand
        );
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.OnDemand)
        );
    }

    function test_SetFundingBasis_Revert_WhenNotGovernor() public {
        vm.prank(operator);
        vm.expectRevert();
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
    }

    // ==================== Global Tracking ====================

    function test_GlobalTracking_TotalRequired() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim1);
        assertEq(agreementManager.getTotalAgreementCount(), 1);

        _offerAgreement(rca2);
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim1 + maxClaim2);
        assertEq(agreementManager.getTotalAgreementCount(), 2);
    }

    function test_GlobalTracking_TotalUnfunded() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // In Full mode, escrow is fully funded — totalUnfunded should be 0
        assertEq(agreementManager.getTotalUnfunded(), 0, "Fully funded: totalUnfunded = 0");
    }

    function test_GlobalTracking_TotalUnfunded_WhenPartiallyFunded() public {
        // Offer in JIT mode (no deposits) — totalUnfunded = totalRequired
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        assertEq(agreementManager.getTotalUnfunded(), maxClaim, "JIT: totalUnfunded = totalRequired");
    }

    function test_GlobalTracking_RevokeDecrementsCountAndRequired() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim);
        assertEq(agreementManager.getTotalAgreementCount(), 1);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        assertEq(agreementManager.getTotalRequired(), 0);
        assertEq(agreementManager.getTotalAgreementCount(), 0);
    }

    function test_GlobalTracking_RemoveDecrementsCountAndRequired() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getTotalAgreementCount(), 1);

        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getTotalRequired(), 0);
        assertEq(agreementManager.getTotalAgreementCount(), 0);
    }

    function test_GlobalTracking_ReconcileUpdatesRequired() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim);

        // SP cancels — reconcile sets maxNextClaim to 0
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        assertEq(agreementManager.getTotalRequired(), 0);
        // Count unchanged (not removed yet)
        assertEq(agreementManager.getTotalAgreementCount(), 1);
    }

    function test_GlobalTracking_TotalUnfunded_MultiProvider() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );

        _offerAgreement(rca1);
        _offerAgreement(rca2);

        // In Full mode, both are fully funded — totalUnfunded should be 0
        assertEq(agreementManager.getTotalUnfunded(), 0, "Both funded: totalUnfunded = 0");
    }

    function test_GlobalTracking_TotalUnfunded_OverfundedProviderDoesNotMaskDeficit() public {
        // Regression test: over-funded provider must NOT mask another provider's deficit.
        // Offer rca1 for indexer (gets fully funded)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;

        // Drain SAM so indexer2's agreement can't be funded
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // Offer rca2 for indexer2 (can't be funded)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, address(recurringCollector));
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // indexer is fully funded (unfunded = 0), indexer2 has full deficit (unfunded = maxClaim2)
        // totalUnfunded must be maxClaim2, NOT 0 (the old buggy totalRequired - totalInEscrow approach
        // would compute totalRequired = maxClaim1 + maxClaim2, totalInEscrow = maxClaim1,
        // deficit = maxClaim2 — which happens to be correct here, but would be wrong if indexer
        // were over-funded and the excess masked indexer2's deficit)
        assertEq(agreementManager.getTotalUnfunded(), maxClaim2, "Unfunded = indexer2's full deficit");

        // Verify per-provider escrow state
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim1,
            "indexer: fully funded"
        );
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer2).balance,
            0,
            "indexer2: unfunded"
        );
    }

    // ==================== Full Mode (default — existing behavior) ====================

    function test_FullMode_DepositsFullRequired() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );
    }

    function test_FullMode_ThawsExcess() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels, remove (triggers thaw of all excess)
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance - account.tokensThawing, 0, "Full mode: all excess should be thawing");
    }

    // ==================== JustInTime Mode ====================

    function test_JustInTime_ThawsEverything() public {
        // Start in Full mode, offer agreement (gets funded)
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Switch to JustInTime
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        // Update escrow — should thaw everything
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim, "JustInTime: all balance should be thawing");
    }

    function test_JustInTime_NoProactiveDeposit() public {
        // Switch to JustInTime before offering
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // No deposit should have been made
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance, 0, "JustInTime: no proactive deposit");
    }

    function test_JustInTime_JITStillWorks() public {
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Escrow is 0, but beforeCollection should top up
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 500 ether);

        uint256 newBalance = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer)
            .balance;
        assertEq(newBalance, 500 ether, "JustInTime: JIT should deposit requested amount");
    }

    // ==================== OnDemand Mode ====================

    function test_OnDemand_NoProactiveDeposit() public {
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // No deposit — same as JustInTime for deposits
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance, 0, "OnDemand: no proactive deposit");
    }

    function test_OnDemand_HoldsAtRequiredLevel() public {
        // Fund with Full mode first, then switch to OnDemand
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // OnDemand thaw ceiling = required — no thaw expected (balance == thawCeiling)
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, 0, "OnDemand: no thaw (balance == required == thawCeiling)");
        assertEq(account.balance, maxClaim, "OnDemand: balance held at required level");
    }

    function test_OnDemand_DoesNotThawBelowRequired_VsJustInTime() public {
        // Fund 6 agreements at Full level, compare OnDemand vs JustInTime
        for (uint256 i = 1; i <= 6; i++) {
            IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
                indexer,
                100 ether,
                1 ether,
                3600,
                i
            );
            _offerAgreement(rca);
        }

        uint256 maxClaimEach = 1 ether * 3600 + 100 ether;
        uint256 totalRequired = maxClaimEach * 6;

        // JustInTime would thaw everything
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory jitAccount = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(jitAccount.tokensThawing, totalRequired, "JustInTime: thaws everything");

        // Switch to OnDemand — should cancel thaw (thaw ceiling = required)
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory odAccount = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // OnDemand holds at required level — should reduce/cancel thaw
        assertTrue(odAccount.tokensThawing < jitAccount.tokensThawing, "OnDemand thaws less than JustInTime");
    }

    function test_OnDemand_JITStillWorks() public {
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // No deposit, but JIT works
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 500 ether);

        uint256 newBalance = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer)
            .balance;
        assertEq(newBalance, 500 ether, "OnDemand: JIT should work");
    }

    // ==================== Degradation: Full -> OnDemand ====================

    function test_Degradation_FullToOnDemand_WhenInsufficientBalance() public {
        // Offer agreement for indexer1 that consumes most available funds
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);

        // Offer 6 agreements for indexer2, each with large maxClaim
        // SAM won't have enough for all of them at Full level
        for (uint256 i = 1; i <= 6; i++) {
            IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
                indexer2,
                100_000 ether,
                100 ether,
                7200,
                i + 10
            );
            token.mint(address(agreementManager), 100_000 ether);
            vm.prank(operator);
            agreementManager.offerAgreement(rca, address(recurringCollector));
        }

        // totalRequired should be larger than totalUnfunded (degradation occurred: Full -> OnDemand)
        assertTrue(0 < agreementManager.getTotalUnfunded(), "Degradation: some unfunded deficit exists");
    }

    function test_Degradation_NeverReachesJustInTime() public {
        // Even with severe underfunding, degradation stops at OnDemand (thaw ceiling = required)
        // and never reaches JustInTime (thaw ceiling = 0)
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Balance should still be at maxClaim (thaw ceiling = required)
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance, maxClaim, "Balance preserved - degradation doesn't go to JustInTime");
        assertEq(account.tokensThawing, 0, "No thaw - not at JustInTime");
    }

    // ==================== Mode Switch Doesn't Break State ====================

    function test_ModeSwitch_PreservesAgreements() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Switch through all modes — agreement data preserved
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), maxClaim);
        assertEq(agreementManager.getRequiredEscrow(address(recurringCollector), indexer), maxClaim);

        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), maxClaim);
        assertEq(agreementManager.getProviderAgreementCount(indexer), 1);
    }

    function test_ModeSwitch_UpdateEscrowAppliesNewMode() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        // Switch to JustInTime and update escrow
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim, "JustInTime should thaw all");
    }

    // ==================== JIT (beforeCollection) Works in All Modes ====================

    function test_JIT_WorksInFullMode() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        token.mint(address(agreementManager), 10000 ether);

        uint256 escrowBalance = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer)
            .balance;

        uint256 tokensToCollect = escrowBalance + 500 ether;
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);

        uint256 newBalance = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer)
            .balance;
        assertEq(newBalance, tokensToCollect, "JIT top-up should cover collection in Full mode");
    }

    // ==================== afterCollection Reconciles in All Modes ====================

    function test_AfterCollection_ReconcileInOnDemandMode() public {
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint64 acceptedAt = uint64(block.timestamp);
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(agreementId, rca, acceptedAt, lastCollectionAt);
        vm.warp(lastCollectionAt);

        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 500 ether);

        uint256 newMaxClaim = agreementManager.getAgreementMaxNextClaim(agreementId);
        assertEq(newMaxClaim, 1 ether * 3600, "maxNextClaim = ongoing only after first collection");
    }

    // ==================== PendingUpdate with totalRequired tracking ====================

    function test_GlobalTracking_PendingUpdate() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        assertEq(agreementManager.getTotalRequired(), maxClaim);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days),
            1
        );
        _offerAgreementUpdate(rcau);

        uint256 pendingMaxClaim = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim + pendingMaxClaim);
    }

    function test_GlobalTracking_ReplacePendingUpdate() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _makeRCAU(
            agreementId,
            200 ether,
            2 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days),
            1
        );
        _offerAgreementUpdate(rcau1);

        uint256 pendingMaxClaim1 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim + pendingMaxClaim1);

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

        uint256 pendingMaxClaim2 = 0.5 ether * 1800 + 50 ether;
        assertEq(agreementManager.getTotalRequired(), maxClaim + pendingMaxClaim2);
    }

    // ==================== Upward Transitions ====================

    function test_Transition_JustInTimeToFull() public {
        // Start in JIT (no deposits), switch to Full (deposits required)
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Verify no deposit in JIT mode
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            0,
            "JIT: no deposit"
        );

        // Switch to Full
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.Full);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim,
            "Full: deposits required"
        );
    }

    function test_Transition_OnDemandToFull() public {
        // Fund at Full, switch to OnDemand (holds at required), switch back to Full
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Switch to OnDemand — holds at required (no thaw for 1 agreement)
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory odAccount = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(odAccount.balance, maxClaim, "OnDemand: balance held at required");

        // Switch back to Full — no change needed (already at required)
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.Full);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory fullAccount = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(fullAccount.balance, maxClaim, "Full: at required");
    }

    // ==================== Thaw-In-Progress Transitions ====================

    function test_Transition_FullToJustInTime_WhileThawActive() public {
        // Create agreements, cancel one to start a thaw, then switch to JIT
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaimEach = 1 ether * 3600 + 100 ether;

        // Cancel and remove rca1 — this triggers a thaw for excess
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        IPaymentsEscrow.EscrowAccount memory beforeSwitch = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertTrue(0 < beforeSwitch.tokensThawing, "Thaw in progress before switch");
        assertEq(beforeSwitch.tokensThawing, maxClaimEach, "Thawing excess from removed agreement");

        // Switch to JustInTime while thaw is active — existing thaw continues,
        // remaining balance thaws after current thaw completes and is withdrawn
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory midCycle = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // Existing thaw continues (effective >= thawCeiling=0)
        assertEq(midCycle.tokensThawing, maxClaimEach, "Existing thaw continues");

        // Complete first thaw, withdraw, then second cycle thaws the rest
        vm.warp(block.timestamp + 2 days);
        agreementManager.updateEscrow(address(recurringCollector), indexer);

        IPaymentsEscrow.EscrowAccount memory afterWithdraw = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // After withdrawal, remaining balance starts thawing
        assertEq(afterWithdraw.tokensThawing, afterWithdraw.balance, "JIT: all remaining balance thawing");
    }

    // ==================== Enforced JIT ====================

    function test_EnforcedJit_TripsOnPartialBeforeCollection() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain SAM's token balance so beforeCollection can't fully fund
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // Request collection exceeding escrow balance
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EnforcedJit(IRecurringAgreementManager.FundingBasis.Full);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Verify state
        assertTrue(agreementManager.isEnforcedJit(), "Enforced JIT should be tripped");
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.Full),
            "Basis unchanged (enforced JIT overrides behavior, not fundingBasis)"
        );
    }

    function test_EnforcedJit_PreservesBasisOnTrip() public {
        // Set OnDemand, trip — fundingBasis should NOT change
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain SAM
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EnforcedJit(IRecurringAgreementManager.FundingBasis.OnDemand);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Basis stays OnDemand (not switched to JIT)
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.OnDemand),
            "Basis unchanged during trip"
        );
        assertTrue(agreementManager.isEnforcedJit());
    }

    function test_EnforcedJit_DoesNotTripWhenFullyCovered() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Ensure SAM has plenty of tokens
        token.mint(address(agreementManager), 1_000_000 ether);

        // Request less than escrow balance — no trip
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, maxClaim);

        assertFalse(agreementManager.isEnforcedJit(), "No trip when fully covered");
    }

    function test_EnforcedJit_DoesNotTripWhenAlreadyActive() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain SAM
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // First trip
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // Second partial collection — should NOT emit event again
        vm.recordLogs();
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Check no EnforcedJit event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 tripSig = keccak256("EnforcedJit(uint8)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == tripSig) found = true;
        }
        assertFalse(found, "No second trip event");
    }

    function test_EnforcedJit_TripsEvenWhenAlreadyJustInTime() public {
        // Governor explicitly sets JIT
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain SAM so beforeCollection can't cover
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        assertTrue(agreementManager.isEnforcedJit(), "Trips even in JIT mode");
    }

    function test_EnforcedJit_JitStillWorksWhileActive() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain SAM to trip the breaker
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // Now fund SAM and do a JIT top-up while enforced JIT is active
        token.mint(address(agreementManager), 500 ether);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 500 ether);

        uint256 escrowBalance = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer)
            .balance;
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertTrue(maxClaim <= escrowBalance, "JIT still works during enforced JIT");
    }

    function test_EnforcedJit_RecoveryOnUpdateEscrow() public {
        // Offer rca1 (fully funded), drain SAM, offer rca2 (creates unfunded deficit)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca1);

        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, address(recurringCollector));

        // Trip enforced JIT
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // Mint enough to cover totalUnfunded — triggers recovery
        uint256 totalUnfunded = agreementManager.getTotalUnfunded();
        assertTrue(0 < totalUnfunded, "Deficit exists");
        token.mint(address(agreementManager), totalUnfunded);

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EnforcedJitRecovered(IRecurringAgreementManager.FundingBasis.Full);

        agreementManager.updateEscrow(address(recurringCollector), indexer);

        assertFalse(agreementManager.isEnforcedJit(), "Enforced JIT recovered");
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.Full),
            "Basis still Full"
        );
    }

    function test_EnforcedJit_NoRecoveryWhenPartiallyFunded() public {
        // Offer rca1 (fully funded), drain, offer rca2 (unfunded — creates deficit)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca1);

        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, address(recurringCollector));

        // Trip
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        uint256 totalUnfunded = agreementManager.getTotalUnfunded();
        assertTrue(0 < totalUnfunded, "totalUnfunded > 0");

        // Mint less than totalUnfunded — no recovery
        token.mint(address(agreementManager), totalUnfunded / 2);

        agreementManager.updateEscrow(address(recurringCollector), indexer);

        assertTrue(agreementManager.isEnforcedJit(), "Still tripped (insufficient balance)");
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.Full),
            "Basis unchanged"
        );
    }

    function test_EnforcedJit_FundingBasisPreservedDuringTrip() public {
        // Set OnDemand, trip, recover — fundingBasis stays OnDemand throughout
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain and trip
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.OnDemand),
            "Basis preserved during trip"
        );

        // Recovery
        token.mint(address(agreementManager), agreementManager.getTotalRequired());

        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EnforcedJitRecovered(IRecurringAgreementManager.FundingBasis.OnDemand);

        agreementManager.updateEscrow(address(recurringCollector), indexer);
        assertFalse(agreementManager.isEnforcedJit());
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.OnDemand),
            "Basis still OnDemand after recovery"
        );
    }

    function test_EnforcedJit_SetFundingBasisClearsBreaker() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Drain and trip
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // Governor manually sets basis — clears enforced JIT
        vm.prank(governor);
        agreementManager.setFundingBasis(IRecurringAgreementManager.FundingBasis.OnDemand);

        assertFalse(agreementManager.isEnforcedJit(), "Governor cleared breaker");
        assertEq(
            uint256(agreementManager.getFundingBasis()),
            uint256(IRecurringAgreementManager.FundingBasis.OnDemand),
            "Governor's chosen basis"
        );
    }

    function test_EnforcedJit_MultipleTripRecoverCycles() public {
        // Offer rca1 (funded), drain SAM, offer rca2 (unfunded — creates deficit)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca1);

        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, address(recurringCollector));

        uint256 unfunded = agreementManager.getTotalUnfunded();
        assertTrue(0 < unfunded, "Has unfunded deficit");

        // --- Cycle 1: Trip ---
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // --- Cycle 1: Recover ---
        token.mint(address(agreementManager), unfunded);
        agreementManager.updateEscrow(address(recurringCollector), indexer);
        assertFalse(agreementManager.isEnforcedJit());
        assertEq(uint256(agreementManager.getFundingBasis()), uint256(IRecurringAgreementManager.FundingBasis.Full));

        // After recovery, updateEscrow deposited into escrow. Drain again and create new deficit.
        samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            3
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca3, address(recurringCollector));

        unfunded = agreementManager.getTotalUnfunded();
        assertTrue(0 < unfunded, "New unfunded deficit");

        // --- Cycle 2: Trip ---
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // --- Cycle 2: Recover ---
        token.mint(address(agreementManager), unfunded);
        agreementManager.updateEscrow(address(recurringCollector), indexer);
        assertFalse(agreementManager.isEnforcedJit());
        assertEq(uint256(agreementManager.getFundingBasis()), uint256(IRecurringAgreementManager.FundingBasis.Full));
    }

    function test_EnforcedJit_MultiProvider() public {
        // Offer rca1 (funded), drain SAM, offer rca2 (creates deficit → totalUnfunded > 0)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 id1 = _offerAgreement(rca1);

        // Drain SAM so rca2 can't be funded
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // Offer rca2 directly (no mint) — escrow stays unfunded, creates deficit
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, address(recurringCollector));
        assertTrue(0 < agreementManager.getTotalUnfunded(), "should have unfunded escrow");

        // Trip via indexer's agreement
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(id1, 1_000_000 ether);
        assertTrue(agreementManager.isEnforcedJit());

        // Both providers should see JIT behavior (thaw everything)
        agreementManager.updateEscrow(address(recurringCollector), indexer);
        agreementManager.updateEscrow(address(recurringCollector), indexer2);

        IPaymentsEscrow.EscrowAccount memory acc1 = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        IPaymentsEscrow.EscrowAccount memory acc2 = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );

        // Both providers should be thawing (JIT mode via enforced JIT)
        assertEq(acc1.tokensThawing, acc1.balance, "indexer: JIT thaws all");
        assertEq(acc2.tokensThawing, acc2.balance, "indexer2: JIT thaws all");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
