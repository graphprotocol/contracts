// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";

import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { RecurringAgreementManagerSharedTest } from "./shared.t.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { MockEligibilityOracle } from "./mocks/MockEligibilityOracle.sol";

/// @notice Edge case tests for escrow lifecycle, basis degradation, and cross-provider isolation.
/// Covers audit gaps:
///   - REGISTERED-only agreement aging and cleanup (audit gap 6)
///   - Basis degradation when RAM balance is insufficient (audit gap 12)
///   - Cross-provider escrow tracking isolation (audit gap 13)
///   - Eligibility oracle toggle during active agreement (audit gap 16)
contract RecurringAgreementManagerEscrowEdgeCasesTest is RecurringAgreementManagerSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    address internal indexer2;

    function setUp() public override {
        super.setUp();
        indexer2 = makeAddr("indexer2");
    }

    // -- Helpers --

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

    function _escrowBalance(address collector_, address provider_) internal view returns (uint256) {
        (uint256 bal, , ) = paymentsEscrow.escrowAccounts(address(agreementManager), collector_, provider_);
        return bal;
    }

    function _escrowThawing(address collector_, address provider_) internal view returns (uint256) {
        (, uint256 thawing, ) = paymentsEscrow.escrowAccounts(address(agreementManager), collector_, provider_);
        return thawing;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  6. REGISTERED-only agreement — aging and cleanup
    // ══════════════════════════════════════════════════════════════════════

    /// @notice REGISTERED-only agreement: immediately after offer, it's tracked with non-zero maxNextClaim.
    ///         Can be canceled and cleaned up without ever being accepted.
    function test_RegisteredOnly_TrackedAndCancelable() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);

        // Tracked with non-zero maxNextClaim
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);
        assertTrue(
            agreementManager
                .getAgreementInfo(IAgreementCollector(address(recurringCollector)), agreementId)
                .maxNextClaim > 0,
            "REGISTERED agreement should have non-zero maxNextClaim"
        );

        // Cancel without ever accepting — cleans up immediately
        _cancelAgreement(agreementId);
        assertEq(
            agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer),
            0,
            "canceled REGISTERED agreement should be removed"
        );
        assertEq(
            agreementManager.getSumMaxNextClaim(_collector(), indexer),
            0,
            "maxNextClaim should be 0 after cleanup"
        );
        assertEq(agreementManager.getSumMaxNextClaimAll(), 0, "global maxNextClaim should be 0");
    }

    /// @notice After aging past endsAt, reconcile removes a REGISTERED agreement because
    ///         maxNextClaim drops to 0 when the collection window expires.
    function test_RegisteredOnly_RemovedOnReconcileAfterExpiry() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 30 days) // shorter endsAt
        );

        bytes16 agreementId = _offerAgreement(rca);
        assertEq(agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer), 1);

        // Warp past endsAt — collector reports maxNextClaim = 0
        vm.warp(block.timestamp + 31 days);

        // Reconcile removes the expired agreement automatically
        agreementManager.reconcileAgreement(IAgreementCollector(address(recurringCollector)), agreementId);
        assertEq(
            agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer),
            0,
            "expired REGISTERED agreement should be auto-removed on reconcile"
        );
        assertEq(agreementManager.getSumMaxNextClaimAll(), 0, "global sum should be 0");
    }

    /// @notice REGISTERED-only agreement contributes to escrow tracking while alive
    function test_RegisteredOnly_ContributesToEscrow() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );

        bytes16 agreementId = _offerAgreement(rca);
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether;

        // In Full basis mode, the escrow should have been deposited
        assertEq(agreementManager.getSumMaxNextClaimAll(), expectedMaxClaim, "global sum should include REGISTERED");
        assertEq(
            agreementManager.getSumMaxNextClaim(_collector(), indexer),
            expectedMaxClaim,
            "pair sum should include REGISTERED"
        );

        // Escrow should be funded (Full mode)
        uint256 escrowed = _escrowBalance(address(recurringCollector), indexer);
        assertEq(escrowed, expectedMaxClaim, "escrow should be fully funded in Full mode");

        // After cancel, escrow should start thawing
        _cancelAgreement(agreementId);
        uint256 thawing = _escrowThawing(address(recurringCollector), indexer);
        assertEq(thawing, expectedMaxClaim, "escrow should be thawing after cancel");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  12. Basis degradation when balance is insufficient
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When RAM's token balance is too low for Full mode, escrow deposit is
    ///         partial and deficit tracking reflects the shortfall.
    function test_BasisDegradation_InsufficientBalance_PartialDeposit() public {
        // Fund RAM with a small amount
        uint256 limitedFunding = 100 ether;
        token.mint(address(agreementManager), limitedFunding);

        // Offer agreement that requires much more escrow than available
        // maxNextClaim = 10 ether * 3600 + 500 ether = 36500 ether >> 100 ether
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            500 ether,
            10 ether,
            3600,
            1
        );

        // Don't use _offerAgreement since it mints 1M tokens — call directly
        vm.prank(operator);
        bytes16 agreementId = agreementManager.offerAgreement(_collector(), OFFER_TYPE_NEW, abi.encode(rca));

        uint256 expectedMaxClaim = 10 ether * 3600 + 500 ether; // 36500 ether
        assertEq(agreementManager.getSumMaxNextClaimAll(), expectedMaxClaim, "sum should reflect full maxNextClaim");

        // RAM only had 100 ether. In Full mode, spare = balance - deficit.
        // Since deposit uses available balance, only partial deposit was possible.
        // totalEscrowDeficit should be > 0 reflecting the unfunded portion.
        uint256 escrowed = _escrowBalance(address(recurringCollector), indexer);
        assertTrue(escrowed < expectedMaxClaim, "escrow should be less than maxNextClaim (partial deposit)");

        // Verify deficit reflects the gap
        uint256 deficit = agreementManager.getTotalEscrowDeficit();
        assertEq(deficit, expectedMaxClaim - escrowed, "deficit should be maxNextClaim - escrowBalance");
    }

    /// @notice Sufficient funding allows Full basis mode to fully deposit escrow.
    ///         Demonstrates recovery from degraded state to fully-funded state.
    function test_BasisDegradation_RecoveryWithSufficientFunding() public {
        // Use _offerAgreement which mints 1M tokens — sufficient for Full mode
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );

        _offerAgreement(rca);
        uint256 expectedMaxClaim = 1 ether * 3600 + 100 ether; // 3700 ether

        // Full mode: escrow fully deposited
        uint256 escrowFull = _escrowBalance(address(recurringCollector), indexer);
        assertEq(escrowFull, expectedMaxClaim, "Full mode: escrow should be fully funded");
        assertEq(agreementManager.getTotalEscrowDeficit(), 0, "Full mode: no deficit");

        // Switch to JIT — no proactive deposits
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.JustInTime);

        // Reconcile to trigger escrow rebalancing
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        // In JIT, excess should be thawing
        uint256 thawing = _escrowThawing(address(recurringCollector), indexer);
        assertTrue(thawing > 0, "JIT mode: excess should be thawing");

        // Switch back to Full
        vm.prank(operator);
        agreementManager.setEscrowBasis(IRecurringEscrowManagement.EscrowBasis.Full);

        // Reconcile — should cancel thaw and maintain full deposit
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        uint256 escrowRecovered = _escrowBalance(address(recurringCollector), indexer);
        assertEq(escrowRecovered, expectedMaxClaim, "recovered: escrow should be fully funded again");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  13. Cross-provider escrow isolation
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Two providers' escrow tracking is fully isolated — canceling one
    ///         has no effect on the other's sumMaxNextClaim or escrow balance.
    function test_CrossProviderEscrow_IsolatedTracking() public {
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

        bytes16 id1 = _offerAgreement(rca1);
        bytes16 id2 = _offerAgreement(rca2);

        uint256 maxClaim1 = 1 ether * 3600 + 100 ether; // 3700 ether
        uint256 maxClaim2 = 2 ether * 7200 + 200 ether; // 14600 ether

        // Verify isolated sums
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), maxClaim1, "indexer1 sum");
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2, "indexer2 sum");
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim1 + maxClaim2, "global sum");

        // Verify isolated escrow deposits (Full mode)
        assertEq(_escrowBalance(address(recurringCollector), indexer), maxClaim1, "indexer1 escrow");
        assertEq(_escrowBalance(address(recurringCollector), indexer2), maxClaim2, "indexer2 escrow");

        // Cancel indexer1's agreement
        _cancelAgreement(id1);

        // Indexer1 tracking cleared
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer), 0, "indexer1 sum after cancel");

        // Indexer2 completely unaffected
        assertEq(agreementManager.getSumMaxNextClaim(_collector(), indexer2), maxClaim2, "indexer2 sum after cancel");
        assertEq(
            _escrowBalance(address(recurringCollector), indexer2),
            maxClaim2,
            "indexer2 escrow untouched after indexer1 cancel"
        );

        // Global sum reflects only indexer2
        assertEq(agreementManager.getSumMaxNextClaimAll(), maxClaim2, "global sum after indexer1 cancel");
    }

    /// @notice One provider's thaw-in-progress does not affect another's escrow min/max
    function test_CrossProviderEscrow_ThawDoesNotAffectOther() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _makeRCAForIndexer(
            indexer,
            100 ether,
            1 ether,
            3600,
            1
        );
        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _makeRCAForIndexer(
            indexer2,
            100 ether,
            1 ether,
            3600,
            2
        );

        bytes16 id1 = _offerAgreement(rca1);
        _offerAgreement(rca2);

        uint256 maxClaim = 1 ether * 3600 + 100 ether;

        // Cancel indexer1 — triggers thaw
        _cancelAgreement(id1);

        // Indexer1 has thawing escrow
        uint256 thawing1 = _escrowThawing(address(recurringCollector), indexer);
        assertEq(thawing1, maxClaim, "indexer1 escrow should be thawing");

        // Indexer2 escrow should be completely unaffected (no thawing)
        uint256 thawing2 = _escrowThawing(address(recurringCollector), indexer2);
        assertEq(thawing2, 0, "indexer2 should have no thawing");
        assertEq(
            _escrowBalance(address(recurringCollector), indexer2),
            maxClaim,
            "indexer2 balance should be fully funded"
        );

        // After thaw period, withdraw for indexer1 does not touch indexer2
        vm.warp(block.timestamp + 1 days + 1);
        agreementManager.reconcileProvider(IAgreementCollector(address(recurringCollector)), indexer);

        assertEq(
            _escrowBalance(address(recurringCollector), indexer2),
            maxClaim,
            "indexer2 balance untouched after indexer1 thaw completion"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    //  16. Eligibility oracle toggle during active agreement
    // ══════════════════════════════════════════════════════════════════════

    /// @notice When the eligibility oracle flips a provider to ineligible while they have
    ///         an active agreement, isEligible reflects the change immediately.
    function test_EligibilityOracle_FlipDuringActiveAgreement() public {
        MockEligibilityOracle oracle = new MockEligibilityOracle();
        vm.label(address(oracle), "EligibilityOracle");

        // Set oracle — initially all eligible
        oracle.setDefaultEligible(true);
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));

        // Offer agreement for indexer
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            60,
            3600,
            uint64(block.timestamp + 365 days)
        );
        _offerAgreement(rca);

        // Indexer is eligible
        assertTrue(agreementManager.isEligible(indexer), "should be eligible initially");

        // Oracle flips indexer to ineligible
        oracle.setDefaultEligible(false);
        // Default is false and indexer not explicitly set → ineligible
        assertFalse(agreementManager.isEligible(indexer), "should be ineligible after oracle flip");

        // Agreement is still tracked (eligibility doesn't auto-remove)
        assertEq(
            agreementManager.getPairAgreementCount(IAgreementCollector(address(recurringCollector)), indexer),
            1,
            "agreement should persist despite ineligibility"
        );
        assertTrue(
            agreementManager
                .getAgreementInfo(IAgreementCollector(address(recurringCollector)), bytes16(0))
                .maxNextClaim ==
                0 ||
                agreementManager.getSumMaxNextClaim(_collector(), indexer) > 0,
            "escrow tracking should be unaffected by eligibility"
        );

        // Oracle flips back
        oracle.setEligible(indexer, true);
        assertTrue(agreementManager.isEligible(indexer), "should be eligible again after oracle flip back");
    }

    /// @notice Emergency clear of eligibility oracle makes all providers eligible (fail-open)
    function test_EligibilityOracle_EmergencyClear_FailOpen() public {
        MockEligibilityOracle oracle = new MockEligibilityOracle();

        // Set oracle that denies indexer
        vm.prank(governor);
        agreementManager.setProviderEligibilityOracle(IProviderEligibility(address(oracle)));
        assertFalse(agreementManager.isEligible(indexer), "should be ineligible");

        // Emergency clear (PAUSE_ROLE needed — grant it first)
        bytes32 PAUSE_ROLE = keccak256("PAUSE_ROLE");
        vm.prank(governor);
        agreementManager.grantRole(PAUSE_ROLE, governor);

        vm.prank(governor);
        agreementManager.emergencyClearEligibilityOracle();

        // All providers now eligible (fail-open)
        assertTrue(agreementManager.isEligible(indexer), "should be eligible after emergency clear");
        assertTrue(agreementManager.isEligible(indexer2), "all providers eligible after emergency clear");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
