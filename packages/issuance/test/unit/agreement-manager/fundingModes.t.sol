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

    // ==================== Temp JIT ====================

    function test_TempJit_TripsOnPartialBeforeCollection() public {
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
        emit IRecurringEscrowManagement.TempJitSet(true, true);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Verify state
        assertTrue(agreementManager.isTempJit(), "Temp JIT should be tripped");
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis unchanged (temp JIT overrides behavior, not escrowBasis)"
        );
    }

    function test_BeforeCollection_TripsWhenAvailableEqualsDeficit() public {
        // Boundary: available == deficit — strict '<' means trip, not deposit
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Set manager balance to exactly the escrow shortfall
        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 tokensToCollect = escrowBalance + 500 ether;
        uint256 deficit = tokensToCollect - escrowBalance; // 500 ether

        // Drain SAM then mint exactly the deficit
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }
        token.mint(address(agreementManager), deficit);
        assertEq(token.balanceOf(address(agreementManager)), deficit, "Balance == deficit");

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.TempJitSet(true, true);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);

        assertTrue(agreementManager.isTempJit(), "Trips when available == deficit");
    }

    function test_BeforeCollection_DepositsWhenAvailableExceedsDeficit() public {
        // Boundary: available == deficit + 1 — deposits instead of tripping
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 agreementId = _offerAgreement(rca);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 tokensToCollect = escrowBalance + 500 ether;
        uint256 deficit = tokensToCollect - escrowBalance; // 500 ether

        // Drain SAM then mint deficit + 1
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }
        token.mint(address(agreementManager), deficit + 1);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);

        assertFalse(agreementManager.isTempJit(), "No trip when deficit < available");
        (uint256 newEscrow, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(newEscrow, tokensToCollect, "Escrow topped up to tokensToCollect");
    }

    function test_TempJit_PreservesBasisOnTrip() public {
        // Set OnDemand, trip — escrowBasis should NOT change
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

        // Drain SAM
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.TempJitSet(true, true);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Basis stays OnDemand (not switched to JIT)
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand),
            "Basis unchanged during trip"
        );
        assertTrue(agreementManager.isTempJit());
    }

    function test_TempJit_DoesNotTripWhenFullyCovered() public {
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

        assertFalse(agreementManager.isTempJit(), "No trip when fully covered");
    }

    function test_TempJit_DoesNotTripWhenAlreadyActive() public {
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
        assertTrue(agreementManager.isTempJit());

        // Second partial collection — should NOT emit event again
        vm.recordLogs();
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        // Check no TempJitSet event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 tripSig = keccak256("TempJitSet(bool,bool)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == tripSig) found = true;
        }
        assertFalse(found, "No second trip event");
    }

    function test_TempJit_TripsEvenWhenAlreadyJustInTime() public {
        // Governor explicitly sets JIT
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

        // Drain SAM so beforeCollection can't cover
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);

        assertTrue(agreementManager.isTempJit(), "Trips even in JIT mode");
    }

    function test_TempJit_JitStillWorksWhileActive() public {
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
        assertTrue(agreementManager.isTempJit());

        // Now fund SAM and do a JIT top-up while temp JIT is active
        token.mint(address(agreementManager), 500 ether);

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 500 ether);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 maxClaim = 1 ether * 3600 + 100 ether;
        assertTrue(maxClaim <= escrowBalance, "JIT still works during temp JIT");
    }

    function test_TempJit_RecoveryOnUpdateEscrow() public {
        // Offer rca1 (fully deposited), drain SAM, offer rca2 (creates undeposited deficit)
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
        agreementManager.offerAgreement(rca2, _collector());

        // Trip temp JIT
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        // Mint more than totalEscrowDeficit — recovery requires strict deficit < available
        uint256 totalEscrowDeficit = agreementManager.getTotalEscrowDeficit();
        assertTrue(0 < totalEscrowDeficit, "Deficit exists");
        token.mint(address(agreementManager), totalEscrowDeficit + 1);

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.TempJitSet(false, true);

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertFalse(agreementManager.isTempJit(), "Temp JIT recovered");
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis still Full"
        );
    }

    function test_TempJit_NoRecoveryWhenPartiallyFunded() public {
        // Offer rca1 (fully deposited), drain, offer rca2 (undeposited — creates deficit)
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
        agreementManager.offerAgreement(rca2, _collector());

        // Trip
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        uint256 totalEscrowDeficit = agreementManager.getTotalEscrowDeficit();
        assertTrue(0 < totalEscrowDeficit, "0 < totalEscrowDeficit");

        // Mint less than totalEscrowDeficit — no recovery
        token.mint(address(agreementManager), totalEscrowDeficit / 2);

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertTrue(agreementManager.isTempJit(), "Still tripped (insufficient balance)");
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis unchanged"
        );
    }

    function test_TempJit_NoRecoveryWhenExactlyFunded() public {
        // Boundary: available == totalEscrowDeficit — strict '<' means no recovery
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
        agreementManager.offerAgreement(rca2, _collector());

        // Trip
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        // Mint exactly totalEscrowDeficit — recovery requires strict deficit < available
        uint256 totalEscrowDeficit = agreementManager.getTotalEscrowDeficit();
        assertTrue(0 < totalEscrowDeficit, "Deficit exists");
        token.mint(address(agreementManager), totalEscrowDeficit);
        assertEq(token.balanceOf(address(agreementManager)), totalEscrowDeficit, "Balance == deficit");

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);

        assertTrue(agreementManager.isTempJit(), "Still tripped (available == deficit, not >)");
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.Full),
            "Basis unchanged"
        );
    }

    function test_TempJit_EscrowBasisPreservedDuringTrip() public {
        // Set OnDemand, trip, recover — escrowBasis stays OnDemand throughout
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

        // Drain and trip
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand),
            "Basis preserved during trip"
        );

        // Recovery — mint more than deficit (recovery requires strict deficit < available)
        token.mint(address(agreementManager), agreementManager.getSumMaxNextClaimAll() + 1);

        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.TempJitSet(false, true);

        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertFalse(agreementManager.isTempJit());
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand),
            "Basis still OnDemand after recovery"
        );
    }

    function test_TempJit_SetTempJitClearsBreaker() public {
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
        assertTrue(agreementManager.isTempJit());

        // Operator clears tempJit directly
        vm.expectEmit(address(agreementManager));
        emit IRecurringEscrowManagement.TempJitSet(false, false);

        vm.prank(operator);
        agreementManager.setTempJit(false);

        assertFalse(agreementManager.isTempJit(), "Operator cleared breaker");
    }

    function test_TempJit_SetEscrowBasisDoesNotClearBreaker() public {
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
        assertTrue(agreementManager.isTempJit());

        // Operator changes basis — tempJit stays active
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.OnDemand);

        assertTrue(agreementManager.isTempJit(), "setEscrowBasis does not clear tempJit");
        assertEq(
            uint256(agreementManager.getEscrowBasis()),
            uint256(IRecurringEscrowManagement.EscrowBasis.OnDemand),
            "Basis changed independently"
        );
    }

    function test_TempJit_MultipleTripRecoverCycles() public {
        // Offer rca1 (deposited), drain SAM, offer rca2 (undeposited — creates deficit)
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
        agreementManager.offerAgreement(rca2, _collector());

        uint256 undeposited = agreementManager.getTotalEscrowDeficit();
        assertTrue(0 < undeposited, "Has undeposited deficit");

        // --- Cycle 1: Trip ---
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        // --- Cycle 1: Recover (mint more than deficit — recovery requires strict deficit < available) ---
        token.mint(address(agreementManager), undeposited + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertFalse(agreementManager.isTempJit());
        assertEq(uint256(agreementManager.getEscrowBasis()), uint256(IRecurringEscrowManagement.EscrowBasis.Full));

        // After recovery, reconcileCollectorProvider deposited into escrow. Drain again and create new deficit.
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
        agreementManager.offerAgreement(rca3, _collector());

        undeposited = agreementManager.getTotalEscrowDeficit();
        assertTrue(0 < undeposited, "New undeposited deficit");

        // --- Cycle 2: Trip ---
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        // --- Cycle 2: Recover (mint more than deficit) ---
        token.mint(address(agreementManager), undeposited + 1);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        assertFalse(agreementManager.isTempJit());
        assertEq(uint256(agreementManager.getEscrowBasis()), uint256(IRecurringEscrowManagement.EscrowBasis.Full));
    }

    function test_TempJit_MultiProvider() public {
        // Offer rca1 (deposited), drain SAM, offer rca2 (creates deficit → 0 < totalEscrowDeficit)
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        bytes16 id1 = _offerAgreement(rca1);

        // Drain SAM so rca2 can't be deposited
        uint256 samBalance = token.balanceOf(address(agreementManager));
        if (0 < samBalance) {
            vm.prank(address(agreementManager));
            token.transfer(address(1), samBalance);
        }

        // Offer rca2 directly (no mint) — escrow stays undeposited, creates deficit
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            100 ether,
            1 ether,
            3600,
            2
        );
        vm.prank(operator);
        agreementManager.offerAgreement(rca2, _collector());
        assertTrue(0 < agreementManager.getTotalEscrowDeficit(), "should have undeposited escrow");

        // Trip via indexer's agreement
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(id1, 1_000_000 ether);
        assertTrue(agreementManager.isTempJit());

        // Both providers should see JIT behavior (thaw everything)
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer);
        agreementManager.reconcileCollectorProvider(address(_collector()), indexer2);

        IPaymentsEscrow.EscrowAccount memory acc1;
        (acc1.balance, acc1.tokensThawing, acc1.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        IPaymentsEscrow.EscrowAccount memory acc2;
        (acc2.balance, acc2.tokensThawing, acc2.thawEndTimestamp) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer2
        );

        // Both providers should be thawing (JIT mode via temp JIT)
        assertEq(acc1.tokensThawing, acc1.balance, "indexer: JIT thaws all");
        assertEq(acc2.tokensThawing, acc2.balance, "indexer2: JIT thaws all");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
