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

    /* solhint-enable graph/func-name-mixedcase */
}
