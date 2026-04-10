// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";

import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { MockIssuanceAllocator } from "./mocks/MockIssuanceAllocator.sol";

/// @notice Gas regression canary for RAM callbacks (beforeCollection / afterCollection).
/// RecurringCollector caps gas forwarded to these callbacks at 1.5M (MAX_CALLBACK_GAS).
///
/// These tests use mocks for PaymentsEscrow, IssuanceAllocator, and RecurringCollector,
/// so measured gas is lower than production. They catch RAM code regressions (new loops,
/// extra external calls, etc.) but cannot validate the production gas margin.
///
/// Production-representative gas measurements live in the testing package:
/// packages/testing/test/gas/CallbackGas.t.sol (uses real PaymentsEscrow, RecurringCollector,
/// and IssuanceAllocator via RealStackHarness).
contract RecurringAgreementManagerCallbackGasTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Gas budget that RecurringCollector forwards to each callback.
    /// Must match MAX_CALLBACK_GAS in RecurringCollector.
    uint256 internal constant MAX_CALLBACK_GAS = 1_500_000;

    /// @notice Alarm threshold — 1/10th of the callback gas budget.
    /// Current mock worst-case is ~70k. Crossing 150k means RAM code got significantly
    /// heavier and the production gas margin (against real contracts) must be re-evaluated.
    uint256 internal constant GAS_ALARM_THRESHOLD = MAX_CALLBACK_GAS / 10; // 150_000

    MockIssuanceAllocator internal mockAllocator;

    function setUp() public override {
        super.setUp();
        mockAllocator = new MockIssuanceAllocator(token, address(agreementManager));
        vm.label(address(mockAllocator), "MockIssuanceAllocator");

        vm.prank(governor);
        agreementManager.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockAllocator)));
    }

    // ==================== beforeCollection gas ====================

    /// @notice Worst-case beforeCollection: escrow short, triggers distributeIssuance + JIT deposit.
    function test_BeforeCollection_GasWithinBudget_JitDeposit() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        (uint256 escrowBalance, , ) = paymentsEscrow.escrowAccounts(
            address(agreementManager),
            address(recurringCollector),
            indexer
        );

        mockAllocator.setMintPerDistribution(1000 ether);
        vm.roll(block.number + 1);

        uint256 tokensToCollect = escrowBalance + 500 ether;

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, tokensToCollect);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_ALARM_THRESHOLD, "beforeCollection (JIT) exceeds 1/10th of callback gas budget");
    }

    /// @notice beforeCollection early-return path: escrow sufficient, no external calls.
    function test_BeforeCollection_GasWithinBudget_EscrowSufficient() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        agreementManager.beforeCollection(agreementId, 1 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, GAS_ALARM_THRESHOLD, "beforeCollection (sufficient) exceeds 1/10th of callback gas budget");
    }

    // ==================== afterCollection gas ====================

    /// @notice Worst-case afterCollection: reconcile + full escrow update (rebalance path).
    function test_AfterCollection_GasWithinBudget_FullReconcile() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        uint64 acceptedAt = uint64(block.timestamp);
        uint64 lastCollectionAt = uint64(block.timestamp + 1 hours);
        _setAgreementCollected(agreementId, rca, acceptedAt, lastCollectionAt);
        vm.warp(lastCollectionAt);

        mockAllocator.setMintPerDistribution(1000 ether);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 500 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(
            gasUsed,
            GAS_ALARM_THRESHOLD,
            "afterCollection (full reconcile) exceeds 1/10th of callback gas budget"
        );
    }

    /// @notice afterCollection when agreement was canceled by SP — reconcile zeros out maxNextClaim.
    function test_AfterCollection_GasWithinBudget_CanceledBySP() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, ) = _makeRCAWithId(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);
        _setAgreementCanceledBySP(agreementId, rca);

        mockAllocator.setMintPerDistribution(1000 ether);
        vm.roll(block.number + 1);

        uint256 gasBefore = gasleft();
        vm.prank(address(recurringCollector));
        agreementManager.afterCollection(agreementId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(
            gasUsed,
            GAS_ALARM_THRESHOLD,
            "afterCollection (canceled by SP) exceeds 1/10th of callback gas budget"
        );
    }

    /* solhint-enable graph/func-name-mixedcase */
}
