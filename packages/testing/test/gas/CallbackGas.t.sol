// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { RealStackHarness } from "../harness/RealStackHarness.t.sol";

/// @notice Gas measurement for RAM callbacks against real contracts.
/// RecurringCollector forwards at most MAX_PAYER_CALLBACK_GAS (1.5M) to each callback.
/// These tests verify the real contract stack stays within that budget.
///
/// Real contracts on callback path: PaymentsEscrow, IssuanceAllocator, RecurringCollector.
/// Stubs (not on callback path): Controller, HorizonStaking, GraphToken (bare ERC20).
contract CallbackGasTest is RealStackHarness {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Must match MAX_PAYER_CALLBACK_GAS in RecurringCollector.
    uint256 internal constant MAX_PAYER_CALLBACK_GAS = 1_500_000;

    /// @notice Assert callbacks use less than half the budget.
    /// Leaves margin for cold storage and EVM repricing.
    uint256 internal constant GAS_THRESHOLD = MAX_PAYER_CALLBACK_GAS / 2; // 750_000

    // ==================== beforeCollection ====================

    /// @notice Worst-case beforeCollection: escrow short, triggers distributeIssuance + JIT deposit.
    function test_BeforeCollection_GasWithinBudget_JitDeposit() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        IPaymentsEscrow.EscrowAccount memory account = ram.getEscrowAccount(
            IRecurringCollector(address(recurringCollector)),
            indexer
        );

        // Advance block so distributeIssuance actually runs (not deduped)
        vm.roll(block.number + 1);

        uint256 tokensToCollect = account.balance + 500 ether;

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId, tokensToCollect);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (JIT) exceeds half of callback gas budget");
    }

    /// @notice beforeCollection early-return path: escrow sufficient.
    function test_BeforeCollection_GasWithinBudget_EscrowSufficient() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId, 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (sufficient) exceeds half of callback gas budget");
    }

    // ==================== afterCollection ====================

    /// @notice Worst-case afterCollection: reconcile against real RecurringCollector + escrow update.
    /// Exercises real RecurringCollector.getAgreement() / getMaxNextClaim() and real
    /// PaymentsEscrow.adjustThaw() / deposit().
    function test_AfterCollection_GasWithinBudget_FullReconcile() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        // Accept on the real RecurringCollector using ContractApproval path (empty signature).
        // RAM.approveAgreement returns the selector when the hash is authorized.
        vm.prank(dataService);
        recurringCollector.accept(rca, "");

        // Advance time past minSecondsPerCollection, then simulate post-collection
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId, 500 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (full reconcile) exceeds half of callback gas budget");
    }

    // ==================== beforeCollection: cold discovery path ====================

    /// @notice beforeCollection on an agreement with a cold provider: exercises first-seen
    /// escrow slot access + JIT deposit. This is the heaviest beforeCollection path.
    function test_BeforeCollection_GasWithinBudget_ColdDiscoveryJit() public {
        // Set up a second provider so we get cold escrow storage
        address indexer2 = makeAddr("indexer2");
        _setUpProvider(indexer2);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.serviceProvider = indexer2;
        rca2.nonce = 2;

        // Offer via RAM — triggers discovery for the new provider
        bytes16 agreementId2 = _offerAgreement(rca2);

        // Advance block so distributeIssuance runs
        vm.roll(block.number + 1);

        IPaymentsEscrow.EscrowAccount memory account = ram.getEscrowAccount(
            IRecurringCollector(address(recurringCollector)),
            indexer2
        );
        uint256 tokensToCollect = account.balance + 500 ether;

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.beforeCollection(agreementId2, tokensToCollect);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "beforeCollection (cold provider JIT) exceeds half of callback gas budget");
    }

    // ==================== afterCollection: withdraw + deposit path ====================

    /// @notice afterCollection exercising the heaviest escrow mutation path:
    /// Two agreements for the same provider. Cancel one → escrow excess triggers thaw.
    /// After thaw matures, afterCollection on the remaining agreement hits withdraw + deposit.
    function test_AfterCollection_GasWithinBudget_WithdrawAndDeposit() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId1 = _offerAndAccept(rca1);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca2.nonce = 2;
        bytes16 agreementId2 = _offerAndAccept(rca2);

        // Cancel agreement 2 by SP — reduces escrow needs, triggers thaw of excess
        vm.prank(dataService);
        recurringCollector.cancel(agreementId2, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        // Advance past the thawing period so the thaw matures
        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);

        // afterCollection on the remaining agreement: should hit withdraw + deposit path
        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId1, 0);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (withdraw + deposit) exceeds half of callback gas budget");
    }

    // ==================== afterCollection: deletion cascade ====================

    /// @notice afterCollection after SP cancels → maxNextClaim → 0, triggers deletion cascade.
    function test_AfterCollection_GasWithinBudget_DeletionCascade() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // SP cancels → state becomes CanceledByServiceProvider, maxNextClaim → 0
        vm.prank(dataService);
        recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        ram.afterCollection(agreementId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_THRESHOLD, "afterCollection (deletion cascade) exceeds half of callback gas budget");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
