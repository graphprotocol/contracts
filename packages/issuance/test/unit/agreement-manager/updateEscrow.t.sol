// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";

contract RecurringAgreementManagerUpdateEscrowTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Basic Thaw / Withdraw ====================

    function test_UpdateEscrow_ThawsExcessWhenNoAgreements() public {
        // Create agreement, fund escrow, then remove it
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Verify escrow was funded
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        // SP cancels — removeAgreement triggers escrow update, thawing the full balance
        _setAgreementCanceledBySP(agreementId, rca);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);

        // balance should now be fully thawing
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance - account.tokensThawing, 0);
    }

    function test_UpdateEscrow_WithdrawsCompletedThaw() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // SP cancels and remove (triggers thaw)
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        // Fast forward past thawing period (1 day in mock)
        vm.warp(block.timestamp + 1 days + 1);

        uint256 agreementManagerBalanceBefore = token.balanceOf(address(agreementManager));

        // updateEscrow: withdraw
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EscrowWithdrawn(indexer, address(recurringCollector), maxClaim);

        agreementManager.updateEscrow(_collector(), indexer);

        // Tokens should be back in RecurringAgreementManager
        uint256 agreementManagerBalanceAfter = token.balanceOf(address(agreementManager));
        assertEq(agreementManagerBalanceAfter - agreementManagerBalanceBefore, maxClaim);
    }

    function test_UpdateEscrow_NoopWhenNoBalance() public {
        // No agreements, no balance — should succeed silently
        agreementManager.updateEscrow(_collector(), indexer);
    }

    function test_UpdateEscrow_NoopWhenStillThawing() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // SP cancels and remove (triggers thaw)
        _setAgreementCanceledBySP(agreementId, rca);
        agreementManager.removeAgreement(agreementId);

        // Subsequent call before thaw complete: no-op (thaw in progress, amount is correct)
        agreementManager.updateEscrow(_collector(), indexer);

        // Balance should still be fully thawing
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.balance - account.tokensThawing, 0);
    }

    function test_UpdateEscrow_Permissionless() public {
        // Anyone can call updateEscrow
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        agreementManager.updateEscrow(_collector(), indexer);
    }

    // ==================== Excess Thawing With Active Agreements ====================

    function test_UpdateEscrow_ThawsExcessWithActiveAgreements() public {
        // Offer agreement, accept, then reconcile down — excess should be thawed
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Accept and simulate a collection (reduces maxNextClaim)
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        uint64 collectionTime = uint64(block.timestamp + 1800);
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp), collectionTime);
        vm.warp(collectionTime);

        // Reconcile — should reduce required escrow
        agreementManager.reconcileAgreement(agreementId);
        uint256 newRequired = agreementManager.sumMaxNextClaim(_collector(), indexer);
        assertTrue(newRequired < maxClaim, "Required should have decreased");

        // Escrow balance is still maxClaim — excess exists
        // The reconcileAgreement call already invoked _updateEscrow which thawed the excess
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 expectedExcess = maxClaim - newRequired;
        assertEq(account.tokensThawing, expectedExcess, "Excess should be thawing");

        // Liquid balance should equal required
        uint256 liquid = account.balance - account.tokensThawing;
        assertEq(liquid, newRequired, "Liquid balance should equal required");
    }

    // ==================== Partial Cancel ====================

    function test_OfferAgreement_PartialCancelPreservesThawTimer() public {
        // Setup: two agreements, reconcile one down to create excess, thaw it
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaimEach = 1 ether * 3600 + 100 ether;

        // SP cancels agreement 1, reconcile to 0, then remove (triggers thaw of excess)
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);
        agreementManager.removeAgreement(id1);

        // Verify excess is thawing
        IPaymentsEscrow.EscrowAccount memory accountBefore = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(accountBefore.tokensThawing, maxClaimEach, "Excess should be thawing");
        uint256 thawEndBefore = accountBefore.thawEndTimestamp;
        assertTrue(0 < thawEndBefore, "Thaw should be in progress");

        // Now offer a small new agreement — should partial-cancel, NOT restart timer
        IRecurringCollector.RecurringCollectionAgreement memory rca3 = _makeRCA(
            10 ether,
            0.1 ether,
            60,
            1800,
            uint64(block.timestamp + 180 days)
        );
        rca3.nonce = 3;
        _offerAgreement(rca3);

        uint256 maxClaim3 = 0.1 ether * 1800 + 10 ether;

        // Check that thaw was partially canceled (not fully canceled)
        IPaymentsEscrow.EscrowAccount memory accountAfter = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // New required = maxClaimEach + maxClaim3
        // Excess = 2*maxClaimEach - (maxClaimEach + maxClaim3) = maxClaimEach - maxClaim3
        uint256 expectedThawing = maxClaimEach - maxClaim3;
        assertEq(accountAfter.tokensThawing, expectedThawing, "Thaw should be partially canceled");

        // Timer should be preserved (not reset)
        assertEq(accountAfter.thawEndTimestamp, thawEndBefore, "Thaw timer should be preserved");

        // Liquid balance should cover new required
        uint256 newRequired = agreementManager.sumMaxNextClaim(_collector(), indexer);
        uint256 liquid = accountAfter.balance - accountAfter.tokensThawing;
        assertEq(liquid, newRequired, "Liquid should cover required");
    }

    function test_UpdateEscrow_FullCancelWhenDeficit() public {
        // Setup: agreement funded, then increase required beyond balance
        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 id1 = _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;

        // SP cancels, reconcile to 0, remove (triggers thaw of all excess)
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);
        agreementManager.removeAgreement(id1);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim1, "All should be thawing");

        // Now offer a new agreement larger than what's in escrow
        // This will make balance < required, so all thawing should be canceled
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            500 ether,
            5 ether,
            60,
            7200,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        _offerAgreement(rca2);

        // Thaw should have been fully canceled
        account = paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertEq(account.tokensThawing, 0, "Thaw should be fully canceled for deficit");
    }

    function test_UpdateEscrow_SkipsThawIncreaseToPreserveTimer() public {
        // Setup: two agreements, thaw excess from removing first
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);
        uint256 maxClaimEach = 1 ether * 3600 + 100 ether;

        // Remove agreement 1 to create excess (triggers thaw)
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.reconcileAgreement(id1);
        agreementManager.removeAgreement(id1);

        IPaymentsEscrow.EscrowAccount memory accountBefore = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(accountBefore.tokensThawing, maxClaimEach);
        uint256 thawEndBefore = accountBefore.thawEndTimestamp;

        // Advance time halfway through thawing
        vm.warp(block.timestamp + 12 hours);

        // Remove agreement 2 — excess grows to 2*maxClaimEach
        // Uses evenIfTimerReset=false internally, so thaw increase is skipped
        bytes16 id2 = bytes16(
            recurringCollector.generateAgreementId(
                rca2.payer,
                rca2.dataService,
                rca2.serviceProvider,
                rca2.deadline,
                rca2.nonce
            )
        );
        _setAgreementCanceledBySP(id2, rca2);
        agreementManager.reconcileAgreement(id2);
        agreementManager.removeAgreement(id2);

        IPaymentsEscrow.EscrowAccount memory accountAfter = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Timer preserved — thaw increase was skipped to avoid resetting it
        assertEq(accountAfter.thawEndTimestamp, thawEndBefore, "Thaw timer should be preserved");
        // Thaw amount stays at original (increase skipped)
        assertEq(accountAfter.tokensThawing, maxClaimEach, "Thaw should stay at original amount");
    }

    // ==================== Data-driven: _updateEscrow combinations ====================
    //
    // Tests all (escrowBasis, accountState) combinations via a helper that:
    //   1. Sets escrowBasis (controls min/max)
    //   2. Overrides mock escrow to desired (balance, tokensThawing, thawReady)
    //   3. Calls updateEscrow
    //   4. Asserts expected (balance, tokensThawing)
    //
    // Desired behavior (the 4 objectives):
    //   Obj 1: liquid stays in [min, max]
    //   Obj 2: withdraw excess above min if thaw completed
    //   Obj 3: never increase thaw amount (would reset timer)
    //   Obj 4: minimize transactions — no needless deposit/thaw/cancel

    function _check(
        IRecurringAgreementManager.EscrowBasis basis,
        uint256 bal,
        uint256 thawing,
        bool ready,
        uint256 expBal,
        uint256 expThaw,
        string memory label
    ) internal {
        uint256 snap = vm.snapshot();

        vm.prank(governor);
        agreementManager.setEscrowBasis(basis);

        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            bal,
            thawing,
            ready ? block.timestamp - 1 : (0 < thawing ? block.timestamp + 1 days : 0)
        );

        agreementManager.updateEscrow(_collector(), indexer);

        IPaymentsEscrow.EscrowAccount memory r = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(r.balance, expBal, string.concat(label, ": balance"));
        assertEq(r.tokensThawing, expThaw, string.concat(label, ": thawing"));

        assertTrue(vm.revertTo(snap));
    }

    /// @dev Like _check but sets thawEndTimestamp to an exact value (for boundary testing)
    function _checkAtTimestamp(
        IRecurringAgreementManager.EscrowBasis basis,
        uint256 bal,
        uint256 thawing,
        uint256 thawEndTimestamp,
        uint256 expBal,
        uint256 expThaw,
        string memory label
    ) internal {
        uint256 snap = vm.snapshot();

        vm.prank(governor);
        agreementManager.setEscrowBasis(basis);

        paymentsEscrow.setAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer,
            bal,
            thawing,
            thawEndTimestamp
        );

        agreementManager.updateEscrow(_collector(), indexer);

        IPaymentsEscrow.EscrowAccount memory r = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(r.balance, expBal, string.concat(label, ": balance"));
        assertEq(r.tokensThawing, expThaw, string.concat(label, ": thawing"));

        assertTrue(vm.revertTo(snap));
    }

    function test_UpdateEscrow_Combinations() public {
        // S = sumMaxNextClaim, established by offering one agreement in Full mode.
        // After offer: escrow balance = S, manager minted 1M in setUp.
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);
        uint256 S = 1 ether * 3600 + 100 ether; // 3700 ether

        // Ensure mock has enough ERC20 for large-balance test cases
        token.mint(address(paymentsEscrow), 10 * S);
        // Ensure block.timestamp > 1 so "thawReady" timestamps are non-zero
        vm.warp(100);

        // ── Full mode: min = S, max = S ─────────────────────────────────
        IRecurringAgreementManager.EscrowBasis F = IRecurringAgreementManager.EscrowBasis.Full;

        //                   basis  bal     thaw    ready   expBal  expThaw
        _check(F, S, 0, false, S, 0, "F1:balanced");
        _check(F, 2 * S, 0, false, 2 * S, S, "F2:excess->thaw");
        _check(F, S / 2, 0, false, S, 0, "F3:deficit->deposit");
        _check(F, 0, 0, false, S, 0, "F4:empty->deposit");
        _check(F, 2 * S, S, false, 2 * S, S, "F5:thaw,liquid=min->leave");
        _check(F, 2 * S, (S * 3) / 2, false, 2 * S, S, "F6:thaw,liquid<min->cancel-to-min");
        _check(F, 2 * S, S, true, S, 0, "F7:ready,liquid=min->withdraw");
        _check(F, S, S, true, S, 0, "F8:ready,liquid=0->cancel-all");
        _check(F, S, S, false, S, 0, "F9:thaw,liquid=0->cancel-all");

        // ── OnDemand mode: min = 0, max = S ─────────────────────────────
        IRecurringAgreementManager.EscrowBasis O = IRecurringAgreementManager.EscrowBasis.OnDemand;

        _check(O, S, 0, false, S, 0, "O1:balanced");
        _check(O, 2 * S, 0, false, 2 * S, S, "O2:excess->thaw");
        _check(O, S / 2, 0, false, S / 2, 0, "O3:no-deposit(min=0)");
        _check(O, 0, 0, false, 0, 0, "O4:empty,no-op");
        _check(O, 2 * S, S, false, 2 * S, S, "O5:thaw,liquid>=min->leave");
        _check(O, 2 * S, (S * 3) / 2, false, 2 * S, (S * 3) / 2, "O6:thaw,liquid>=min->LEAVE(key)");
        _check(O, 2 * S, S, true, S, 0, "O7:ready->withdraw");
        _check(O, S, S, true, 0, 0, "O8:ready,all-thaw->withdraw-all");
        _check(O, S, S, false, S, S, "O9:thaw,liquid=0>=min->leave");

        // ── JIT mode: min = 0, max = 0 ──────────────────────────────────
        IRecurringAgreementManager.EscrowBasis J = IRecurringAgreementManager.EscrowBasis.JustInTime;

        _check(J, S, 0, false, S, S, "J1:thaw-all(max=0)");
        _check(J, 0, 0, false, 0, 0, "J2:empty,no-op");
        _check(J, 2 * S, S, false, 2 * S, 2 * S, "J3:same-block->increase-ok");
        _check(J, S, S, true, 0, 0, "J4:ready->withdraw-all");
        _check(J, 2 * S, S, true, S, S, "J5:ready->withdraw,thaw-rest");

        // ── Boundary: thawEndTimestamp == block.timestamp should withdraw ──
        // Thaw period ends AT this timestamp, so withdraw should fire.
        _checkAtTimestamp(F, 2 * S, S, block.timestamp, S, 0, "B1:boundary-full->withdraw");
        _checkAtTimestamp(O, 2 * S, S, block.timestamp, S, 0, "B2:boundary-ondemand->withdraw");
        _checkAtTimestamp(J, S, S, block.timestamp, 0, 0, "B3:boundary-jit->withdraw-all");
    }

    // ==================== Cross-Indexer Isolation ====================

    function test_UpdateEscrow_CrossIndexerIsolation() public {
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
        _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether;
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether;

        // Remove indexer1's agreement (triggers thaw)
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        IPaymentsEscrow.EscrowAccount memory acct1 = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(acct1.balance - acct1.tokensThawing, 0);

        // Indexer2 escrow should be unaffected
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer2).balance,
            maxClaim2
        );

        // updateEscrow on indexer2 should be a no-op (balance == required)
        agreementManager.updateEscrow(_collector(), indexer2);
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer2).balance,
            maxClaim2
        );
    }

    // ==================== NoopWhenBalanced ====================

    function test_UpdateEscrow_NoopWhenBalanced() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Balance should exactly match required — no excess, no deficit
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        // updateEscrow should be a no-op
        agreementManager.updateEscrow(_collector(), indexer);

        // Nothing changed
        assertEq(
            paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, 0, "No thawing should occur");
    }

    // ==================== Automatic Thaw on Reconcile ====================

    function test_Reconcile_AutomaticallyThawsExcess() public {
        // Reconcile calls _updateEscrow, which should thaw excess automatically
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Accept and simulate a collection
        _setAgreementAccepted(agreementId, rca, uint64(block.timestamp));
        uint64 collectionTime = uint64(block.timestamp + 1800);
        _setAgreementCollected(agreementId, rca, uint64(block.timestamp), collectionTime);
        vm.warp(collectionTime);

        // Reconcile — triggers _updateEscrow internally
        agreementManager.reconcileAgreement(agreementId);

        // Excess should already be thawing
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 newRequired = agreementManager.sumMaxNextClaim(_collector(), indexer);
        uint256 expectedExcess = maxClaim - newRequired;
        assertEq(account.tokensThawing, expectedExcess, "Excess should auto-thaw after reconcile");
    }

    // ==================== Withdraw guard: compare against liquid, not total ====================

    function test_UpdateEscrow_WithdrawsPartialWhenLiquidCoversMin() public {
        // Two agreements: keep the big one, remove the small one.
        // After thaw completes, liquid (= big max claim) >= min -> withdraw proceeds.
        // Only the small agreement's tokens leave escrow; min stays behind.
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca1.nonce = 1;

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;

        _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether; // 3700 ether
        uint256 maxClaim2 = 0.5 ether * 1800 + 50 ether; // 950 ether

        // Cancel and remove rca2 -> excess (950) thawed, rca1 remains
        _setAgreementCanceledBySP(id2, rca2);
        agreementManager.removeAgreement(id2);

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim2, "Excess from rca2 should be thawing");
        assertEq(account.balance - account.tokensThawing, maxClaim1, "Liquid should cover rca1");

        // Wait for thaw to complete
        vm.warp(block.timestamp + 1 days + 1);

        // Expect the withdraw event for the thawed amount
        vm.expectEmit(address(agreementManager));
        emit IRecurringAgreementManager.EscrowWithdrawn(indexer, address(recurringCollector), maxClaim2);

        agreementManager.updateEscrow(_collector(), indexer);

        // After withdraw: only rca1's required amount remains, nothing thawing
        account = paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertEq(account.balance, maxClaim1, "Balance should equal remaining min");
        assertEq(account.tokensThawing, 0, "Nothing should be thawing after withdraw");
    }

    function test_UpdateEscrow_PartialCancelAndWithdrawInOneCall() public {
        // Scenario: all tokens thawing and ready, offer a smaller replacement.
        // _updateEscrow partial-cancels thaw (to balance - min), then withdraws the
        // reduced amount in a single call. No round-trip: balance ends at min, no redeposit.

        (IRecurringCollector.RecurringCollectionAgreement memory rca1, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 id1 = _offerAgreement(rca1);
        uint256 maxClaim1 = 1 ether * 3600 + 100 ether; // 3700 ether

        // Remove -> full thaw
        _setAgreementCanceledBySP(id1, rca1);
        agreementManager.removeAgreement(id1);

        // Verify: entire balance is thawing, liquid = 0
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(account.tokensThawing, maxClaim1, "All should be thawing");
        assertEq(account.balance - account.tokensThawing, 0, "Liquid should be zero");

        // Wait for thaw to complete
        vm.warp(block.timestamp + 1 days + 1);

        // Offer smaller replacement -> _updateEscrow fires
        // Partial-cancels thaw (3700 -> 2750), then withdraws 2750. Balance = 950 = min.
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            50 ether,
            0.5 ether,
            60,
            1800,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        uint256 maxClaim2 = 0.5 ether * 1800 + 50 ether; // 950 ether

        _offerAgreement(rca2);

        account = paymentsEscrow.escrowAccounts(address(agreementManager), address(recurringCollector), indexer);
        assertEq(account.balance, maxClaim2, "Balance should equal min after partial-cancel + withdraw");
        assertEq(account.tokensThawing, 0, "Nothing thawing after withdraw");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
