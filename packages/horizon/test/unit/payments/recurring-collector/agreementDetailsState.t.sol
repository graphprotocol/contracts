// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PROVIDER,
    UPDATE,
    VERSION_CURRENT,
    VERSION_NEXT
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice State-flag semantics for AgreementDetails returned by offer() and getAgreementDetails().
/// Pins down two properties:
///   1. offer() reports the same lifecycle state as getAgreementDetails() for the queried version
///      (REGISTERED, ACCEPTED, UPDATE, NOTICE_GIVEN, BY_*, SETTLED) — not just the version-specific
///      bits.
///   2. SETTLED is per-version: VERSION_CURRENT scopes to active terms, VERSION_NEXT to pending —
///      a non-zero claim on one version must not suppress SETTLED on the other.
contract RecurringCollectorAgreementDetailsStateTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function _makeRca(address payer) internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            _recurringCollectorHelper.sensibleRCA(
                IRecurringCollector.RecurringCollectionAgreement({
                    deadline: uint64(block.timestamp + 1 hours),
                    endsAt: uint64(block.timestamp + 365 days),
                    payer: payer,
                    dataService: makeAddr("ds"),
                    serviceProvider: makeAddr("sp"),
                    maxInitialTokens: 100 ether,
                    maxOngoingTokensPerSecond: 1 ether,
                    minSecondsPerCollection: 600,
                    maxSecondsPerCollection: 3600,
                    conditions: 0,
                    nonce: 1,
                    metadata: ""
                })
            );
    }

    function _makeRcau(
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint64 deadline
    ) internal pure returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: deadline,
                endsAt: rca.endsAt + 30 days,
                maxInitialTokens: rca.maxInitialTokens,
                maxOngoingTokensPerSecond: rca.maxOngoingTokensPerSecond * 2,
                minSecondsPerCollection: rca.minSecondsPerCollection,
                maxSecondsPerCollection: rca.maxSecondsPerCollection,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });
    }

    function _acceptUnsigned(
        MockAgreementOwner approver,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        return _recurringCollector.accept(rca, "");
    }

    // ──────────────────────────────────────────────────────────────────────
    // offer() return state mirrors getAgreementDetails()
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Fresh offer(NEW) on a never-seen agreement returns REGISTERED only.
    function test_OfferNew_FreshOffer_State_Registered() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );

        assertEq(details.state, REGISTERED, "fresh offer(NEW): REGISTERED only");
    }

    /// @notice Fresh offer(UPDATE) on an accepted agreement returns REGISTERED|UPDATE only.
    function test_OfferUpdate_FreshOffer_State_RegisteredUpdate() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(
            agreementId,
            rca,
            uint64(block.timestamp + 1 hours)
        );

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_UPDATE,
            abi.encode(rcau),
            0
        );

        assertEq(details.state, REGISTERED | UPDATE, "fresh offer(UPDATE): REGISTERED|UPDATE");
    }

    /// @notice Re-offering an already-accepted RCA hits the idempotent path and must report
    /// ACCEPTED — the offered version is the active accepted terms.
    function test_OfferNew_AfterAccept_State_RegisteredAccepted() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        _acceptUnsigned(approver, rca);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );

        assertEq(details.state, REGISTERED | ACCEPTED, "re-offer(NEW) after accept: REGISTERED|ACCEPTED");
    }

    /// @notice Re-offering an already-applied RCAU hits the idempotent path; since the RCAU is
    /// now the active terms, the queried version is CURRENT, so state is REGISTERED|ACCEPTED|UPDATE.
    function test_OfferUpdate_AfterApply_State_RegisteredAcceptedUpdate() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(
            agreementId,
            rca,
            uint64(block.timestamp + 1 hours)
        );
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_UPDATE,
            abi.encode(rcau),
            0
        );

        assertEq(
            details.state,
            REGISTERED | ACCEPTED | UPDATE,
            "re-offer(UPDATE) after apply: REGISTERED|ACCEPTED|UPDATE"
        );
    }

    /// @notice Re-offering an RCA after the agreement was canceled by the service provider must
    /// surface NOTICE_GIVEN|BY_PROVIDER (and SETTLED, since active claim is zero in this state).
    function test_OfferNew_AfterProviderCancel_State_FullyDecorated() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes16 agreementId = _acceptUnsigned(approver, rca);

        vm.prank(rca.dataService);
        _recurringCollector.cancel(agreementId, IRecurringCollector.CancelAgreementBy.ServiceProvider);

        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory details = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );

        assertEq(
            details.state,
            REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER | SETTLED,
            "re-offer(NEW) after provider cancel: REGISTERED|ACCEPTED|NOTICE_GIVEN|BY_PROVIDER|SETTLED"
        );
    }

    // ──────────────────────────────────────────────────────────────────────
    // SETTLED is per-version (active vs pending scoping)
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Pending RCAU past its deadline contributes 0 to claim. With per-version SETTLED
    /// scoping, VERSION_NEXT reports SETTLED even though the active terms still have claim.
    /// Pre-fix (unscoped getMaxNextClaim) would have suppressed SETTLED here.
    function test_GetAgreementDetails_VersionNext_SettledIndependentOfActive() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        bytes16 agreementId = _acceptUnsigned(approver, rca);

        uint64 rcauDeadline = uint64(block.timestamp + 1 hours);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(agreementId, rca, rcauDeadline);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Past pending deadline — pending claim is 0, but active claim still grows.
        vm.warp(rcauDeadline + 1);

        IAgreementCollector.AgreementDetails memory next = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_NEXT
        );
        IAgreementCollector.AgreementDetails memory current = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_CURRENT
        );

        assertEq(next.state & SETTLED, SETTLED, "VERSION_NEXT: SETTLED set when pending claim is 0");
        assertEq(current.state & SETTLED, 0, "VERSION_CURRENT: SETTLED not set when active claim is non-zero");
    }

    /// @notice Active terms past their offer deadline (still NotAccepted) have 0 active claim.
    /// With per-version scoping, VERSION_CURRENT reports SETTLED even though a fresh pending
    /// update still has non-zero claim. Pre-fix, the pending claim would have masked SETTLED.
    function test_GetAgreementDetails_VersionCurrent_SettledIndependentOfPending() public {
        MockAgreementOwner approver = new MockAgreementOwner();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRca(address(approver));
        vm.prank(address(approver));
        IAgreementCollector.AgreementDetails memory offered = _recurringCollector.offer(
            OFFER_TYPE_NEW,
            abi.encode(rca),
            0
        );
        bytes16 agreementId = offered.agreementId;

        // Pending update with a far-future deadline — its claim stays non-zero after the warp.
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeRcau(
            agreementId,
            rca,
            uint64(block.timestamp + 30 days)
        );
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Past the RCA's offer deadline — active claim drops to 0 (state still NotAccepted, no
        // valid pre-acceptance offer).
        vm.warp(rca.deadline + 1);

        IAgreementCollector.AgreementDetails memory current = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_CURRENT
        );
        IAgreementCollector.AgreementDetails memory next = _recurringCollector.getAgreementDetails(
            agreementId,
            VERSION_NEXT
        );

        assertEq(current.state & SETTLED, SETTLED, "VERSION_CURRENT: SETTLED set when active claim is 0");
        assertEq(next.state & SETTLED, 0, "VERSION_NEXT: SETTLED not set when pending claim is non-zero");
    }
}
