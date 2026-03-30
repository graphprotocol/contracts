// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    SETTLED,
    AUTO_UPDATE,
    AUTO_UPDATED,
    NOTICE_GIVEN,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    WITH_NOTICE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";
import { Vm } from "forge-std/Vm.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @dev Mock data service that reverts on acceptAgreement
contract RevertingAcceptCallback is IDataServiceAgreements {
    function acceptAgreement(
        bytes16,
        bytes32,
        address,
        address,
        bytes calldata,
        bytes calldata
    ) external pure override {
        revert("reject upgrade");
    }
    function afterAgreementStateChange(bytes16, bytes32, uint16) external pure override {}
}

/// @notice Tests for the auto-update mechanism: AUTO_UPDATE flag, WITH_NOTICE offers,
/// and automatic promotion of pending terms during the final collect.
contract RecurringCollectorAutoUpgradeTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    MockAgreementOwner internal _approver;
    bytes internal _revertingCallbackCode;

    function setUp() public override {
        super.setUp();
        _approver = new MockAgreementOwner();
        _revertingCallbackCode = address(new RevertingAcceptCallback()).code;
    }

    // ============================================================
    // Helper: create a basic accepted agreement with given options
    // ============================================================

    function _makeAcceptedAgreement(
        uint16 options
    ) internal returns (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) {
        rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 30 days),
                payer: address(_approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 1 days,
                nonce: 1,
                metadata: ""
            })
        );

        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(address(_approver));
        agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), options);
    }

    function _offerUpgrade(
        IRecurringCollector.RecurringCollectionAgreement memory,
        bytes16 agreementId,
        uint64 upgradeDeadline,
        uint64 newEndsAt
    ) internal {
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: upgradeDeadline,
                endsAt: newEndsAt,
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 1 days,
                nonce: 1,
                metadata: ""
            });
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), WITH_NOTICE);
    }

    function _collectFull(IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) internal {
        // Decode active terms to get endsAt
        (, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
        uint64 activeEndsAt;
        {
            // Could be OFFER_TYPE_NEW or OFFER_TYPE_UPDATE; both have endsAt at same decode position
            // Use a simpler approach: just decode the endsAt from the active offer
            (uint8 offerType, ) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            if (offerType == OFFER_TYPE_NEW) {
                IRecurringCollector.RecurringCollectionAgreement memory activeRca = abi.decode(
                    offerData,
                    (IRecurringCollector.RecurringCollectionAgreement)
                );
                activeEndsAt = activeRca.endsAt;
            } else {
                IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                    offerData,
                    (IRecurringCollector.RecurringCollectionAgreementUpdate)
                );
                activeEndsAt = activeRcau.endsAt;
            }
        }
        // Warp to endsAt + buffer to ensure we're past it
        vm.warp(activeEndsAt + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));
    }

    // ============================================================
    // accept() options tests
    // ============================================================

    function test_Accept_SetsAutoUpgradeFlag() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );
        rca; // silence unused warning
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & AUTO_UPDATE != 0, "AUTO_UPDATE should be set");
    }

    function test_Accept_NoAutoUpgradeByDefault() public {
        (, bytes16 agreementId) = _makeAcceptedAgreement(0);
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & AUTO_UPDATE == 0, "AUTO_UPDATE should not be set");
    }

    function test_Accept_TogglesAutoUpgradeOnUpdate() public {
        // Accept with AUTO_UPDATE
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        // Offer an update
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 60 days),
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 1 days,
                nonce: 1,
                metadata: ""
            });
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Accept update with options=0 (clear AUTO_UPDATE)
        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        IRecurringCollector.AgreementData memory updatedAgreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(updatedAgreement.state & AUTO_UPDATE == 0, "AUTO_UPDATE should be cleared");
    }

    // ============================================================
    // WITH_NOTICE offer tests
    // ============================================================

    function test_OfferWithNotice_SetsCanceledAt() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        // Active terms are NOT modified — collectableUntil is reduced instead
        assertEq(agreement.collectableUntil, upgradeDeadline, "collectableUntil should be set to deadline");
        assertTrue(agreement.state & NOTICE_GIVEN != 0, "NOTICE_GIVEN should be set");
        (, bytes memory offerData) = _recurringCollector.getAgreementOfferAt(agreementId, 1);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory pendingRcau = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(pendingRcau.endsAt, newEndsAt, "pending endsAt should be the new terms");
    }

    function test_OfferWithNotice_DeadlineZero_AutoComputes() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, 0, newEndsAt);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        // deadline=0 → auto-set collectableUntil to block.timestamp + minSecondsPayerCancellationNotice
        uint64 expectedCollectableUntil = uint64(block.timestamp) + rca.minSecondsPayerCancellationNotice;
        assertEq(
            agreement.collectableUntil,
            expectedCollectableUntil,
            "collectableUntil should be auto-computed from min notice"
        );
    }

    function test_OfferUpgrade_Revert_WhenInsufficientNotice() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        // Deadline is 1 second from now, but min notice is 1 day
        uint64 tooSoonDeadline = uint64(block.timestamp + 1);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: tooSoonDeadline,
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 0,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 1 days,
                nonce: 1,
                metadata: ""
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.InsufficientNotice.selector,
                agreementId,
                rca.minSecondsPayerCancellationNotice,
                uint256(tooSoonDeadline - block.timestamp)
            )
        );
        vm.prank(address(_approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), WITH_NOTICE);
    }

    // ============================================================
    // Auto-upgrade on final collect
    // ============================================================

    function test_Collect_AutoUpgrades_WhenPendingAndFlagSet() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        // Offer upgrade with deadline = now + 2 days
        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        // Warp past the upgrade deadline (which is now the active endsAt)
        vm.warp(upgradeDeadline + 1);

        // Final collect should trigger auto-upgrade
        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AutoUpdateAttempted(agreementId, true);

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // Verify: agreement is NOT settled, active terms are the upgraded ones
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED == 0, "should NOT be settled after upgrade");
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(activeRcau.endsAt, newEndsAt, "active endsAt should be new terms");
            assertEq(activeRcau.maxOngoingTokensPerSecond, 2 ether, "active rate should be new terms");
        }
        // Pending terms should be cleared (only 1 version)
        assertEq(_recurringCollector.getAgreementVersionCount(agreementId), 1, "pending terms should be cleared");
        assertTrue(agreement.state & AUTO_UPDATE != 0, "AUTO_UPDATE should be preserved");
        assertTrue(agreement.state & AUTO_UPDATED != 0, "AUTO_UPDATED should be set after auto-update");
    }

    function test_Collect_Settles_WhenAutoUpgradeCallbackReverts() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        // Replace data service code with reverting callback
        vm.etch(rca.dataService, _revertingCallbackCode);

        vm.warp(upgradeDeadline + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AutoUpdateAttempted(agreementId, false);

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // Collect succeeds but agreement settles
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED != 0, "should be settled when upgrade fails");
    }

    function test_Collect_Settles_WhenNoAutoUpgradeFlag() public {
        // Accept WITHOUT AUTO_UPDATE
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(0);

        // Offer upgrade (pending terms exist but no AUTO_UPDATE flag)
        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        vm.warp(upgradeDeadline + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED != 0, "should settle without AUTO_UPDATE flag");
    }

    function test_Collect_Settles_ExpiredNonTerminated_NoPendingTerms() public {
        // Accept without any pending terms or auto-upgrade
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(0);

        // Just collect after expiry — no pending, no terminate, should settle
        _collectFull(rca, agreementId);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED != 0, "expired agreement should settle on final collect");
    }

    function test_Collect_AutoUpgrade_SucceedsEvenWhenPendingEndsAtPast() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        // Offer upgrade with deadline = now + 2 days, but set pending endsAt to only 3 days from now
        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 shortEndsAt = uint64(block.timestamp + 3 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, shortEndsAt);

        // Warp past both the upgrade deadline AND the pending endsAt
        vm.warp(shortEndsAt + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        // Auto-upgrade succeeds — terms were validated at offer time, data service callback decides
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AutoUpdateAttempted(agreementId, true);

        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED == 0, "should not be settled - upgrade succeeded");
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(activeRcau.endsAt, shortEndsAt, "active endsAt should be the upgraded terms");
        }
    }

    // ============================================================
    // Full lifecycle
    // ============================================================

    function test_FullLifecycle_Offer_Accept_Collect_Upgrade_AutoPromote_Collect() public {
        // 1. Create and accept agreement with AUTO_UPDATE
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        // 2. First collection
        vm.warp(block.timestamp + 1000);
        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("first"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // 3. Offer upgrade
        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        // 4. Final collect triggers auto-upgrade
        vm.warp(upgradeDeadline + 1);
        params.collectionId = bytes32("final");
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // 5. Verify upgraded
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED == 0, "should not be settled");
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(activeRcau.maxOngoingTokensPerSecond, 2 ether, "should have new rate");
        }

        // 6. Collect on new terms
        vm.warp(block.timestamp + 1000);
        params.collectionId = bytes32("post-upgrade");
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // Should still be active
        agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED == 0, "should still be active after post-upgrade collect");
    }

    // ============================================================
    // SETTLED notification suppression on auto-update (decision 4)
    // ============================================================

    /// @notice When auto-update succeeds, the transient SETTLED event should be suppressed.
    ///         Only the revived ACCEPTED state should appear in AgreementUpdated events.
    function test_Collect_AutoUpgrade_SuppressesSettledNotification() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        vm.warp(upgradeDeadline + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.recordLogs();
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // Scan AgreementUpdated events — none should have SETTLED flag set
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 updatedSig = IRecurringCollector.AgreementUpdated.selector;
        bool foundSettled;
        bool foundAccepted;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == updatedSig) {
                // Decode state from event data: AgreementUpdated(bytes16 agreementId, bytes32 versionHash, uint16 state)
                (, uint16 eventState) = abi.decode(logs[i].data, (bytes32, uint16));
                if (eventState & SETTLED != 0) foundSettled = true;
                if (eventState & ACCEPTED != 0 && eventState & SETTLED == 0) foundAccepted = true;
            }
        }
        assertFalse(foundSettled, "SETTLED event should be suppressed when auto-update succeeds");
        assertTrue(foundAccepted, "revived ACCEPTED event should be emitted");
    }

    /// @notice When auto-update fails, the SETTLED event should fire normally.
    function test_Collect_NoAutoUpgrade_EmitsSettledNotification() public {
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(
            AUTO_UPDATE
        );

        uint64 upgradeDeadline = uint64(block.timestamp + 2 days);
        uint64 newEndsAt = uint64(block.timestamp + 365 days);
        _offerUpgrade(rca, agreementId, upgradeDeadline, newEndsAt);

        // Replace data service code with reverting callback → auto-update will fail
        vm.etch(rca.dataService, _revertingCallbackCode);

        vm.warp(upgradeDeadline + 1);

        IRecurringCollector.CollectParams memory params = IRecurringCollector.CollectParams({
            agreementId: agreementId,
            collectionId: bytes32("final"),
            tokens: 0,
            dataServiceCut: 0,
            receiverDestination: rca.serviceProvider,
            maxSlippage: type(uint256).max
        });

        vm.recordLogs();
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, abi.encode(params));

        // Scan AgreementUpdated events — should find one with SETTLED flag
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 updatedSig = IRecurringCollector.AgreementUpdated.selector;
        bool foundSettled;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == updatedSig) {
                (, uint16 eventState) = abi.decode(logs[i].data, (bytes32, uint16));
                if (eventState & SETTLED != 0) foundSettled = true;
            }
        }
        assertTrue(foundSettled, "SETTLED event should fire when auto-update fails");
    }

    /// @notice When no auto-update is attempted (no pending terms, no AUTO_UPDATE), SETTLED fires.
    function test_Collect_NoPending_EmitsSettledNotification() public {
        // Accept WITHOUT AUTO_UPDATE and no pending terms
        (IRecurringCollector.RecurringCollectionAgreement memory rca, bytes16 agreementId) = _makeAcceptedAgreement(0);

        _collectFull(rca, agreementId);

        // Re-read state — agreement should be SETTLED
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreementData(agreementId);
        assertTrue(agreement.state & SETTLED != 0, "should be SETTLED after final collect");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
