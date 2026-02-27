// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { ServiceAgreementManagerSharedTest } from "./shared.t.sol";

contract ServiceAgreementManagerUpdateEscrowTest is ServiceAgreementManagerSharedTest {
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
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        // SP cancels — removeAgreement triggers escrow update, thawing the full balance
        _setAgreementCanceledBySP(agreementId, rca);

        agreementManager.removeAgreement(agreementId);

        assertEq(agreementManager.getProviderAgreementCount(indexer), 0);

        // balance should now be fully thawing
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
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
        emit IServiceAgreementManager.EscrowWithdrawn(indexer, address(recurringCollector), maxClaim);

        agreementManager.updateEscrow(indexer);

        // Tokens should be back in ServiceAgreementManager
        uint256 agreementManagerBalanceAfter = token.balanceOf(address(agreementManager));
        assertEq(agreementManagerBalanceAfter - agreementManagerBalanceBefore, maxClaim);
    }

    function test_UpdateEscrow_NoopWhenNoBalance() public {
        // No agreements, no balance — should succeed silently
        agreementManager.updateEscrow(indexer);
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
        agreementManager.updateEscrow(indexer);

        // Balance should still be fully thawing
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
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
        agreementManager.updateEscrow(indexer);
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
        uint256 newRequired = agreementManager.getRequiredEscrow(indexer);
        assertTrue(newRequired < maxClaim, "Required should have decreased");

        // Escrow balance is still maxClaim — excess exists
        // The reconcileAgreement call already invoked _updateEscrow which thawed the excess
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
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
        IPaymentsEscrow.EscrowAccount memory accountBefore = paymentsEscrow.getEscrowAccount(
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
        IPaymentsEscrow.EscrowAccount memory accountAfter = paymentsEscrow.getEscrowAccount(
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
        uint256 newRequired = agreementManager.getRequiredEscrow(indexer);
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

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
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
        account = paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer);
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

        IPaymentsEscrow.EscrowAccount memory accountBefore = paymentsEscrow.getEscrowAccount(
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

        IPaymentsEscrow.EscrowAccount memory accountAfter = paymentsEscrow.getEscrowAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        // Timer preserved — thaw increase was skipped to avoid resetting it
        assertEq(accountAfter.thawEndTimestamp, thawEndBefore, "Thaw timer should be preserved");
        // Thaw amount stays at original (increase skipped)
        assertEq(accountAfter.tokensThawing, maxClaimEach, "Thaw should stay at original amount");
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

        IPaymentsEscrow.EscrowAccount memory acct1 = paymentsEscrow.getEscrowAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        assertEq(acct1.balance - acct1.tokensThawing, 0);

        // Indexer2 escrow should be unaffected
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer2).balance,
            maxClaim2
        );

        // updateEscrow on indexer2 should be a no-op (balance == required)
        agreementManager.updateEscrow(indexer2);
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer2).balance,
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
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        // updateEscrow should be a no-op
        agreementManager.updateEscrow(indexer);

        // Nothing changed
        assertEq(
            paymentsEscrow.getEscrowAccount(address(agreementManager), address(recurringCollector), indexer).balance,
            maxClaim
        );

        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
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
        IPaymentsEscrow.EscrowAccount memory account = paymentsEscrow.getEscrowAccount(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );
        uint256 newRequired = agreementManager.getRequiredEscrow(indexer);
        uint256 expectedExcess = maxClaim - newRequired;
        assertEq(account.tokensThawing, expectedExcess, "Excess should auto-thaw after reconcile");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
