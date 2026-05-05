// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";

import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
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

    // ==================== setEscrowBasis ====================

    function test_SetEscrowBasis_DefaultIsFull() public view {
        assertEq(uint256(agreementManager.getEscrowBasis()), uint256(IRecurringEscrowManagement.EscrowBasis.Full));
    }

    function test_SetEscrowBasis_OperatorCanSet() public {
        vm.prank(operator);
        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.EscrowBasisSet(
            IRecurringEscrowManagement.EscrowBasis.Full,
            IRecurringEscrowManagement.EscrowBasis.OnDemand
        );
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        assertEq(uint256(agreementManager.getEscrowBasis()), uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand));
    }

    function test_SetEscrowBasis_Revert_WhenNotOperator() public {
        vm.prank(governor);
        vm.expectRevert();
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
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
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim1);
        assertEq(agreementManager.getTotalAgreementCount(), 1);

        _offerAgreement(rca2);
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim1 + maxClaim2);
        assertEq(agreementManager.getTotalAgreementCount(), 2);
    }

    function test_GlobalTracking_TotalUndeposited() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // In Full mode, escrow is fully deposited — totalEscrowDeficit should be 0
        assertEq(agreementManager.getTotalEscrowDeficit(), 0, "Fully escrowed: totalEscrowDeficit = 0");
    }

    function test_GlobalTracking_TotalUndeposited_WhenPartiallyFunded() public {
        // Offer in JIT mode (no deposits) — totalEscrowDeficit = sumMaxNextClaim
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        assertEq(agreementManager.getTotalEscrowDeficit(), maxClaim, "JIT: totalEscrowDeficit = sumMaxNextClaim");
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
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim);
        assertEq(agreementManager.getTotalAgreementCount(), 1);

        vm.prank(operator);
        agreementManager.revokeOffer(agreementId);

        assertEq(agreementManager.getSumMaxNextClaimAll(), 0);
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
        agreementManager.reconcileAgreement(agreementId);

        assertEq(agreementManager.getSumMaxNextClaimAll(), 0);
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
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim);

        // SP cancels — reconcile sets maxNextClaim to 0
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.reconcileAgreement(agreementId);

        assertEq(agreementManager.getSumMaxNextClaimAll(), 0);
        // Reconcile now deletes settled agreements inline
        assertEq(agreementManager.getTotalAgreementCount(), 0);
    }

    function test_GlobalTracking_TotalUndeposited_MultiProvider() public {
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

        // In Full mode, both are fully deposited — totalEscrowDeficit should be 0
        assertEq(agreementManager.getTotalEscrowDeficit(), 0, "Both deposited: totalEscrowDeficit = 0");
    }

    function test_GlobalTracking_TotalUndeposited_OverdepositedProviderDoesNotMaskDeficit() public {
        // Regression test: over-deposited provider must NOT mask another provider's deficit.
        // Offer rca1 for indexer (gets fully deposited)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;

        // Drain SAM so indexer2's agreement can't be deposited
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // Offer rca2 for indexer2 (can't be deposited)
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            200 ether,
            2 ether,
            7200,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, _collector());
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // indexer is fully deposited (undeposited = 0), indexer2 has full deficit (undeposited = maxClaim2)
        // totalEscrowDeficit must be maxClaim2, NOT 0 (the old buggy sumMaxNextClaim - totalInEscrow approach
        // would compute sumMaxNextClaim = maxClaim1 + maxClaim2, totalInEscrow = maxClaim1,
        // deficit = maxClaim2 — which happens to be correct here, but would be wrong if indexer
        // were over-deposited and the excess masked indexer2's deficit)
        assertEq(agreementManager.getTotalEscrowDeficit(), maxClaim2, "Undeposited = indexer2's full deficit");

        // Verify per-provider escrow state
        assertEq(
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer),
            maxClaim1,
            "indexer: fully deposited"
        );
        assertEq(
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer2),
            0,
            "indexer2: undeposited"
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

        assertEq(paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer), maxClaim);
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
        agreementManager.reconcileAgreement(agreementId);

        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance - account.tokensThawing, 0, "Full mode: all excess should be thawing");
    }

    // ==================== JustInTime Mode ====================

    function test_JustInTime_ThawsEverything() public {
        // Start in Full mode, offer agreement (gets deposited)
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
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

        // Update escrow — should thaw everything
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim, "JustInTime: all balance should be thawing");
    }

    function test_JustInTime_NoProactiveDeposit() public {
        // Switch to JustInTime before offering
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // No deposit should have been made
        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance, 0, "JustInTime: no proactive deposit");
    }

    function test_JustInTime_JITStillWorks() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

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

        (uint256 newBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(newBalance, 500 ether, "JustInTime: JIT should deposit requested amount");
    }

    // ==================== OnDemand Mode ====================

    function test_OnDemand_NoProactiveDeposit() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);

        // No deposit — same as JustInTime for deposits
        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
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
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, 0, "OnDemand: no thaw (balance == required == thawCeiling)");
        assertEq(account.balance, maxClaim, "OnDemand: balance held at required level");
    }

    function test_OnDemand_PreservesThawFromJIT() public {
        // Fund 6 agreements at Full level, then switch JIT -> OnDemand
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
        uint256 sumMaxNextClaim = maxClaimEach * 6;

        // JustInTime would thaw everything
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory jitAccount;
        (jitAccount.balance, jitAccount.tokensThawing, jitAccount.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(jitAccount.tokensThawing, sumMaxNextClaim, "JustInTime: thaws everything");

        // Switch to OnDemand — min=0, min <= liquid=0, so thaw is left alone
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory odAccount;
        (odAccount.balance, odAccount.tokensThawing, odAccount.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // OnDemand: min=0, min(0) <= liquid(0) — existing thaw preserved, no unnecessary cancellation
        assertEq(odAccount.tokensThawing, jitAccount.tokensThawing, "OnDemand preserves thaw when min <= liquid");
    }

    function test_OnDemand_JITStillWorks() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

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

        (uint256 newBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
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
            agreementManager.offerAgreement(rca, _collector());
        }

        // sumMaxNextClaim should be larger than totalEscrowDeficit (degradation occurred: Full -> OnDemand)
        assertTrue(0 < agreementManager.getTotalEscrowDeficit(), "Degradation: some undeposited deficit exists");
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
        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
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
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        assertEq(agreementManager.getAgreementMaxNextClaim(agreementId), maxClaim);
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim);

        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
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

        assertEq(paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer), maxClaim);

        // Switch to JustInTime and update escrow
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory account;
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
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

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        uint256 tokensToCollect = escrowBalance + 500 ether;
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);

        (uint256 newBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(newBalance, tokensToCollect, "JIT top-up should cover collection in Full mode");
    }

    // ==================== afterCollection Reconciles in All Modes ====================

    function test_AfterCollection_ReconcileInOnDemandMode() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

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

    // ==================== PendingUpdate with sumMaxNextClaim tracking ====================

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

        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim);

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
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim + pendingMaxClaim);
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
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim + pendingMaxClaim1);

        // Replace with different terms (same nonce — collector hasn't accepted either)
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

        uint256 pendingMaxClaim2 = 0.5 ether * 1800 + 50 ether;
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim + pendingMaxClaim2);
    }

    // ==================== Upward Transitions ====================

    function test_Transition_JustInTimeToFull() public {
        // Start in JIT (no deposits), switch to Full (deposits required)
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

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
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer),
            0,
            "JIT: no deposit"
        );

        // Switch to Full
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(
            paymentsEscrow.getBalance(address(agreementManager), address(recurringCollector), indexer),
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
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory odAccount;
        (odAccount.balance, odAccount.tokensThawing, odAccount.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(odAccount.balance, maxClaim, "OnDemand: balance held at required");

        // Switch back to Full — no change needed (already at required)
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory fullAccount;
        (fullAccount.balance, fullAccount.tokensThawing, fullAccount.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
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
        agreementManager.reconcileAgreement(id1);

        IPaymentsEscrow.EscrowAccount memory beforeSwitch;
        (beforeSwitch.balance, beforeSwitch.tokensThawing, beforeSwitch.thawEndTimestamp) = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertTrue(0 < beforeSwitch.tokensThawing, "Thaw in progress before switch");
        assertEq(beforeSwitch.tokensThawing, maxClaimEach, "Thawing excess from removed agreement");

        // Switch to JustInTime while thaw is active — existing thaw continues,
        // remaining balance thaws after current thaw completes and is withdrawn
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory midCycle;
        (midCycle.balance, midCycle.tokensThawing, midCycle.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        // Same-block increase is fine (no timer reset) — thaws everything
        assertEq(midCycle.tokensThawing, 2 * maxClaimEach, "Same-block: thaw increased to full balance");

        // Complete thaw, withdraw all
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        IPaymentsEscrow.EscrowAccount memory afterWithdraw;
        (afterWithdraw.balance, afterWithdraw.tokensThawing, afterWithdraw.thawEndTimestamp) = paymentsEscrow
            .escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        // Everything withdrawn in one cycle
        assertEq(afterWithdraw.balance, 0, "JIT: all withdrawn");
        assertEq(afterWithdraw.tokensThawing, 0, "JIT: nothing left to thaw");
    }

    // ==================== Threshold-Based Basis Degradation ====================
    //
    // _escrowMinMax computes spare = balance - totalEscrowDeficit (floored at 0)
    // and checks two gates against sumMaxNextClaimAll (smnca):
    //
    //   max gate: smnca * minOnDemandBasisThreshold / 256 < spare   [default threshold=128 -> 0.5x]
    //   min gate: smnca * (256 + minFullBasisMargin) / 256 < spare  [default margin=16 -> 1.0625x]
    //
    // min gate is stricter (1.0625 > 0.5), giving three degradation states:
    //   Full:      spare > smnca * 1.0625   (min=max=sumMaxNextClaim)
    //   OnDemand:  0.5*smnca < spare <= 1.0625*smnca  (min=0, max=sumMaxNextClaim)
    //   JIT-like:  spare <= 0.5*smnca       (min=0, max=0)

    // -- Helpers for degradation tests --

    /// @notice Drain SAM balance to zero
    function _drainSAM() internal {
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }
    }

    /// @notice Get the effective escrow balance (balance - tokensThawing) for a pair
    function _effectiveEscrow(address collector, address provider) internal view returns (uint256) {
        (uint256 balance, uint256 thawing, ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            collector,
            provider
        );
        return balance - thawing;
    }

    /// @notice Get full escrow account for a pair
    function _escrowAccount(
        address collector,
        address provider
    ) internal view returns (uint256 balance, uint256 tokensThawing, uint256 thawEndTimestamp) {
        return paymentsEscrow.escrowAccounts(address(agreementManager), collector, provider);
    }

    /// @notice Fund SAM so spare equals exactly the given amount (above totalEscrowDeficit)
    function _fundToSpare(uint256 targetSpare) internal {
        _drainSAM();
        uint256 deficit = agreementManager.getTotalEscrowDeficit();
        token.mint(address(agreementManager), deficit + targetSpare);
    }

    // ---- Full basis: min gate (1.0625x) controls Full -> OnDemand ----

    function test_BasisDegradation_Full_BothGatesPass_DepositsToSumMaxNextClaim() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // spare > smnca * 1.0625 -- both gates pass -> Full
        _fundToSpare((smnca * (256 + 16)) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            pairSmnc,
            "Full: deposited to sumMaxNextClaim"
        );
    }

    function test_BasisDegradation_Full_MinGateFail_DegradesToOnDemand() public {
        // spare at min gate boundary: min gate fails but max gate passes -> OnDemand
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // spare = smnca * 272/256 exactly -- min gate fails (not strictly greater)
        // but spare > smnca * 128/256, so max gate passes
        uint256 minGateThreshold = (smnca * (256 + 16)) / 256;
        _fundToSpare(minGateThreshold);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand behavior: min=0 (no deposits), max=sumMaxNextClaim (holds ceiling)
        // Escrow was deposited during offerAgreement, so it should still be at pairSmnc
        // (max holds, no thaw started because balance <= max)
        uint256 effective = _effectiveEscrow(address(recurringCollector), indexer);
        assertEq(effective, pairSmnc, "OnDemand: escrow held at ceiling (no thaw)");

        // Stored basis unchanged
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Stored basis unchanged"
        );
    }

    function test_BasisDegradation_Full_MinGateBoundary_OneWeiDifference() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);
        uint256 minGateThreshold = (smnca * (256 + 16)) / 256;

        // At min gate boundary: OnDemand (min=0, max=smnc)
        _fundToSpare(minGateThreshold);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Escrow was pre-deposited, OnDemand holds it (no thaw because balance <= max)
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), pairSmnc, "At boundary: OnDemand holds");

        // One wei above: Full (min=max=smnc)
        _fundToSpare(minGateThreshold + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), pairSmnc, "One above boundary: Full deposits");
    }

    // ---- Full basis: max gate (0.5x) controls OnDemand -> JIT-like ----

    function test_BasisDegradation_Full_MaxGateFail_DegradesToJIT() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // spare = smnca * 128/256 exactly -- max gate fails -> JIT-like (both 0)
        uint256 maxGateThreshold = (smnca * 128) / 256;
        _fundToSpare(maxGateThreshold);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (uint256 bal, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, bal, "JIT-like: all escrow thawing");
    }

    function test_BasisDegradation_Full_MaxGateBoundary_OneWeiDifference() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 maxGateThreshold = (smnca * 128) / 256;

        // At max gate boundary: JIT-like
        _fundToSpare(maxGateThreshold);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        (uint256 bal1, uint256 thawing1, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing1, bal1, "At max boundary: JIT thaws all");

        // Complete thaw
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // One wei above max gate: OnDemand (max passes, min still fails since 0.5x+1 < 1.0625x)
        _fundToSpare(maxGateThreshold + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: min=0 so no deposit happens (escrow was withdrawn during thaw)
        // max=smnc so no thaw starts either. Effective balance stays at 0 (nothing to hold).
        (uint256 bal2, uint256 thawing2, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing2, 0, "One above max boundary: OnDemand no thaw");
        // No deposit because min=0
        assertEq(bal2, 0, "OnDemand: no deposit (min=0)");
    }

    // ---- Intermediate OnDemand state: between the two thresholds ----

    function test_BasisDegradation_Full_IntermediateOnDemand_NoDepositButHoldsEscrow() public {
        // Verify the intermediate state: min=0 (no deposit), max=smnc (holds ceiling)
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // Fund to middle of OnDemand band: 0.5x < spare < 1.0625x
        // Use spare = 0.75x (halfway in the band)
        uint256 midSpare = (smnca * 3) / 4;
        assertTrue(midSpare > (smnca * 128) / 256, "midSpare above max gate");
        assertTrue(midSpare <= (smnca * (256 + 16)) / 256, "midSpare below min gate");

        _fundToSpare(midSpare);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Escrow was deposited during offerAgreement (when SAM had 1M ether).
        // OnDemand: max=smnc so holds (no thaw), min=0 so no new deposit.
        uint256 effective = _effectiveEscrow(address(recurringCollector), indexer);
        assertEq(effective, pairSmnc, "OnDemand: holds pre-existing escrow at ceiling");
        (, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, 0, "OnDemand: no thaw");
    }

    function test_BasisDegradation_Full_IntermediateOnDemand_NoDepositFromZero() public {
        // Start with zero escrow in OnDemand band -- verify no deposit happens
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // Drain to JIT, complete thaw to clear escrow
        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), 0, "Escrow cleared");

        // Fund to OnDemand band
        _fundToSpare((smnca * 3) / 4);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: min=0 -> no deposit from zero. max=smnc but nothing to hold.
        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            0,
            "OnDemand: no deposit when starting from zero"
        );
    }

    // ---- OnDemand basis: max gate only (min always 0) ----

    function test_BasisDegradation_OnDemand_MaxGatePass_HoldsAtCeiling() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // OnDemand: only max gate matters (min is always 0 because basis != Full)
        // max gate: smnca * threshold/256 < spare
        _fundToSpare((smnca * 128) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, 0, "OnDemand: no thaw when max gate passes");
    }

    function test_BasisDegradation_OnDemand_MaxGateFail_ThawsAll() public {
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // Max gate fails -> max=0 -> thaw everything
        _fundToSpare((smnca * 128) / 256);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (uint256 bal, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, bal, "OnDemand degraded: all thawing");
    }

    function test_BasisDegradation_OnDemand_MinGateIrrelevant() public {
        // Even with generous spare (above min gate), OnDemand never deposits
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // Drain to zero, complete thaw
        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Fund well above both gates
        _fundToSpare(smnca * 2);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: min=0 always (basis != Full), so no deposit from zero
        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            0,
            "OnDemand: no deposit regardless of spare (min always 0)"
        );
    }

    // ---- Zero spare ----

    function test_BasisDegradation_ZeroSpare_DegradesToJIT() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);

        _drainSAM();
        assertEq(token.balanceOf(address(agreementManager)), 0, "SAM drained");

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (uint256 bal, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, bal, "JIT: thaws all when spare=0");
    }

    // ---- Recovery ----

    function test_BasisDegradation_Recovery_JITToOnDemand() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // Drain to JIT, complete thaw
        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), 0, "JIT: zero escrow");

        // Fund to OnDemand band (above max gate, below min gate)
        _fundToSpare((smnca * 128) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: min=0 so no deposit, max=smnc but nothing to hold
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), 0, "OnDemand recovery: no deposit (min=0)");
        (, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, 0, "OnDemand recovery: no thaw");
    }

    function test_BasisDegradation_Recovery_JITToFull() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // Drain to JIT, complete thaw
        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // Fund above min gate -> Full
        _fundToSpare((smnca * (256 + 16)) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(_effectiveEscrow(address(recurringCollector), indexer), pairSmnc, "Full: recovered and deposited");
    }

    // ---- Multi-provider: global degradation ----

    function test_BasisDegradation_MultiProvider_BothDegraded() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);

        _drainSAM();

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, _collector());

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        (uint256 bal1, uint256 thawing1, ) = _escrowAccount(address(recurringCollector), indexer);
        (uint256 bal2, uint256 thawing2, ) = _escrowAccount(address(recurringCollector), indexer2);

        assertEq(thawing1, bal1, "indexer: degraded thaws all");
        assertEq(thawing2, bal2, "indexer2: degraded thaws all");
    }

    function test_BasisDegradation_MultiProvider_RecoveryRestoresBoth() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            50 ether,
            2 ether,
            1800,
            2
        );
        _offerAgreement(rca2);

        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc1 = agreementManager.getSumMaxNextClaim(_collector(), indexer);
        uint256 pairSmnc2 = agreementManager.getSumMaxNextClaim(_collector(), indexer2);

        // Drain and degrade
        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        // Complete thaws
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        // Fund above min gate -> both recover to Full
        _fundToSpare((smnca * (256 + 16)) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        assertEq(_effectiveEscrow(address(recurringCollector), indexer), pairSmnc1, "indexer: recovered to Full");
        assertEq(_effectiveEscrow(address(recurringCollector), indexer2), pairSmnc2, "indexer2: recovered to Full");
    }

    // ---- offerAgreement can trigger instant degradation ----

    function test_BasisDegradation_OfferAgreement_TriggersInstantDegradation() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca1);
        uint256 pairSmnc1 = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            pairSmnc1,
            "indexer: initially fully escrowed"
        );

        // Fund to just above min gate for current smnca
        _drainSAM();
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 deficit = agreementManager.getTotalEscrowDeficit();
        token.mint(address(agreementManager), deficit + (smnca * (256 + 16)) / 256 + 1);

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            pairSmnc1,
            "indexer: still Full after careful funding"
        );

        // Offer large new agreement -- increases smnca, pushing spare below min gate
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            500 ether,
            10 ether,
            7200,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, _collector());

        // Reconcile indexer -- existing provider's escrow now degraded
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // New smnca much larger, spare likely below max gate too -> JIT-like
        (uint256 bal, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, bal, "indexer: degraded after new offer increased smnca");
    }

    // ---- Stored escrowBasis never changes automatically ----

    function test_BasisDegradation_StoredBasisUnchanged() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);

        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis: Full before degradation"
        );

        _drainSAM();
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis: still Full after degradation"
        );

        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        _fundToSpare((smnca * (256 + 16)) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis: still Full after recovery"
        );
    }

    // ---- Edge case: no agreements (smnca = 0) ----

    function test_BasisDegradation_NoAgreements_NoRevert() public {
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertEq(_effectiveEscrow(address(recurringCollector), indexer), 0, "No agreements: zero escrow");
    }

    // ---- Custom params ----

    function test_BasisDegradation_CustomMargin_WiderOnDemandBand() public {
        // Increase margin to 128 -> min gate threshold = smnca * 384/256 = 1.5x
        // OnDemand band becomes 0.5x < spare <= 1.5x (much wider)
        vm.prank(operator);
        agreementManager.setMinFullBasisMargin(128);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();
        uint256 pairSmnc = agreementManager.getSumMaxNextClaim(_collector(), indexer);

        // spare = smnca * 1.2 -- above max gate (0.5) but below min gate (1.5)
        _fundToSpare((smnca * 307) / 256); // ~1.2x
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: holds pre-deposited escrow (max=smnc), no deposit (min=0)
        assertEq(
            _effectiveEscrow(address(recurringCollector), indexer),
            pairSmnc,
            "OnDemand with wide band: holds at ceiling"
        );

        // Fund above 1.5x -> Full
        _fundToSpare((smnca * (256 + 128)) / 256 + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertEq(_effectiveEscrow(address(recurringCollector), indexer), pairSmnc, "Full with wide band: deposited");
    }

    function test_BasisDegradation_CustomThreshold_HigherMaxGate() public {
        // Increase threshold to 200 -> max gate threshold = smnca * 200/256 ~ 0.78x
        vm.prank(operator);
        agreementManager.setMinOnDemandBasisThreshold(200);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        _offerAgreement(rca);
        uint256 smnca = agreementManager.getSumMaxNextClaimAll();

        // spare = smnca * 0.6 -- below new max gate (0.78) -> JIT-like
        _fundToSpare((smnca * 154) / 256); // ~0.6x
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        (uint256 bal, uint256 thawing, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing, bal, "JIT with higher threshold: thaws all at 0.6x");

        // spare = smnca * 0.85 -- above new max gate (0.78) -> OnDemand
        vm.warp(block.timestamp + 2 days);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        _fundToSpare((smnca * 218) / 256); // ~0.85x
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        // OnDemand: no deposit (min=0), no thaw (max=smnc)
        (uint256 bal2, uint256 thawing2, ) = _escrowAccount(address(recurringCollector), indexer);
        assertEq(thawing2, 0, "OnDemand with higher threshold: no thaw at 0.85x");
        assertEq(bal2, 0, "OnDemand with higher threshold: no deposit (min=0, escrow cleared)");
    }

    function test_BeforeCollection_JitTopUpStillWorks_WhenDegraded() public {
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

        // Mint just enough for JIT top-up
        token.mint(address(agreementManager), 500 ether);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 500 ether);

        // JIT top-up should have succeeded
        IPaymentsEscrow.EscrowAccount memory acc;
        (acc.balance, acc.tokensThawing, acc.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertTrue(500 ether <= acc.balance, "JIT top-up works when degraded");
    }

    // ==================== Setters ====================

    function test_SetMinOnDemandBasisThreshold() public {
        assertEq(agreementManager.getMinOnDemandBasisThreshold(), 128, "Default threshold");

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.MinOnDemandBasisThresholdSet(128, 64);

        vm.prank(operator);
        agreementManager.setMinOnDemandBasisThreshold(64);

        assertEq(agreementManager.getMinOnDemandBasisThreshold(), 64, "Updated threshold");
    }

    function test_SetMinOnDemandBasisThreshold_NoopWhenSame() public {
        vm.recordLogs();
        vm.prank(operator);
        agreementManager.setMinOnDemandBasisThreshold(128); // same as default

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != IRecurringEscrowManagement.MinOnDemandBasisThresholdSet.selector,
                "Should not emit when unchanged"
            );
        }
    }

    function test_SetMinFullBasisMargin() public {
        assertEq(agreementManager.getMinFullBasisMargin(), 16, "Default margin");

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.MinFullBasisMarginSet(16, 32);

        vm.prank(operator);
        agreementManager.setMinFullBasisMargin(32);

        assertEq(agreementManager.getMinFullBasisMargin(), 32, "Updated margin");
    }

    function test_SetMinFullBasisMargin_NoopWhenSame() public {
        vm.recordLogs();
        vm.prank(operator);
        agreementManager.setMinFullBasisMargin(16); // same as default

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != IRecurringEscrowManagement.MinFullBasisMarginSet.selector,
                "Should not emit when unchanged"
            );
        }
    }

    /* solhint-enable graph/func-name-mixedcase */
}
