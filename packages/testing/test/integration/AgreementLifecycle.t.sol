// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { RecurringCollector } from "horizon/payments/collectors/RecurringCollector.sol";

import { RealStackHarness } from "../harness/RealStackHarness.t.sol";

/// @notice Integration tests using the real contract stack (RAM + RecurringCollector + PaymentsEscrow).
/// Validates cross-contract flows that unit tests with mocks cannot cover.
contract AgreementLifecycleTest is RealStackHarness {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Offer + Accept ====================

    function test_OfferAndAccept() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        IRecurringCollector.AgreementData memory agreement = recurringCollector.getAgreementData(agreementId);
        assertEq(agreement.state, REGISTERED | ACCEPTED);
        assertEq(agreement.payer, address(ram));
        assertEq(agreement.serviceProvider, indexer);
        assertEq(agreement.dataService, dataService);

        // Verify active terms via the offer data
        (, bytes memory offerData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreement memory activeOffer = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        assertEq(activeOffer.endsAt, rca.endsAt);
        assertEq(activeOffer.maxInitialTokens, rca.maxInitialTokens);
        assertEq(activeOffer.maxOngoingTokensPerSecond, rca.maxOngoingTokensPerSecond);
    }

    // ==================== Payer validation ====================

    function test_Offer_Revert_WhenPayerNotRAM() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.payer = address(0xdead);

        // RAM forwards to collector, collector checks msg.sender == rca.payer.
        // msg.sender is RAM, but rca.payer is 0xdead — collector reverts.
        token.mint(address(ram), 1_000_000 ether);
        vm.expectRevert();
        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_NEW, abi.encode(rca));
    }

    // ==================== Offer + Accept + Update ====================

    function test_OfferUpdateAndAccept() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // Offer an update with doubled rate
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));

        // Accept the update
        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.prank(indexer);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // Verify updated terms are now active
        (, bytes memory activeOfferData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory activeUpdate = abi.decode(
            activeOfferData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(activeUpdate.maxOngoingTokensPerSecond, 2 ether);
        assertEq(activeUpdate.maxInitialTokens, 200 ether);
        assertEq(recurringCollector.getAgreementDetails(agreementId, 1).versionHash, bytes32(0)); // cleared
    }

    // ==================== Deadline enforcement ====================

    function test_Accept_Revert_WhenDeadlineElapsed() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        // Warp past deadline
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert();
        vm.prank(indexer);
        recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    function test_AcceptUpdate_Revert_WhenDeadlineElapsed() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));

        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        // Warp past update deadline
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert();
        vm.prank(indexer);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);
    }

    // ==================== Conditions: eligibility check ====================

    function test_Conditions_StoredAndReadBack() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK

        bytes16 agreementId = _offerAndAccept(rca);

        (, bytes memory offerData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreement memory activeOffer = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        assertEq(activeOffer.conditions, 1);
    }

    function test_Conditions_PreservedThroughUpdate() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK
        bytes16 agreementId = _offerAndAccept(rca);

        // Update with different conditions
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                conditions: 0, // Remove eligibility check in update
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));

        // Pending terms have conditions = 0
        {
            (, bytes memory activeOfferData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreement memory activeOffer = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreement)
            );
            assertEq(activeOffer.conditions, 1); // still 1 on active
        }
        {
            (, bytes memory pendingOfferData) = recurringCollector.getAgreementOfferAt(agreementId, 1);
            assertEq(
                abi.decode(pendingOfferData, (IRecurringCollector.RecurringCollectionAgreementUpdate)).conditions,
                0
            ); // 0 on pending
        }

        // Accept update — conditions change
        bytes32 pendingHash = recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.prank(indexer);
        recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        (, bytes memory updatedOfferData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory updatedOffer = abi.decode(
            updatedOfferData,
            (IRecurringCollector.RecurringCollectionAgreementUpdate)
        );
        assertEq(updatedOffer.conditions, 0); // now 0
    }

    function test_Conditions_NoEligibilityCheckWhenFlagNotSet() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        rca.conditions = 0; // No eligibility check

        bytes16 agreementId = _offerAndAccept(rca);

        (, bytes memory offerData) = recurringCollector.getAgreementOfferAt(agreementId, 0);
        IRecurringCollector.RecurringCollectionAgreement memory activeOffer = abi.decode(
            offerData,
            (IRecurringCollector.RecurringCollectionAgreement)
        );
        assertEq(activeOffer.conditions, 0);
    }

    // ==================== Cancel ====================

    function test_CancelByPayer() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        vm.prank(address(ram));
        recurringCollector.cancel(agreementId, activeHash, 0);

        IRecurringCollector.AgreementData memory agreement = recurringCollector.getAgreementData(agreementId);
        assertEq(agreement.state, REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PAYER);
    }

    function test_CancelByServiceProvider() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);
        bytes32 activeHash = recurringCollector.getAgreementDetails(agreementId, 0).versionHash;

        vm.prank(indexer);
        recurringCollector.cancel(agreementId, activeHash, 0);

        IRecurringCollector.AgreementData memory agreement = recurringCollector.getAgreementData(agreementId);
        assertEq(agreement.state, REGISTERED | ACCEPTED | NOTICE_GIVEN | BY_PROVIDER);
    }

    // ==================== Nonce sequencing ====================

    function test_UpdateNonce_MustIncrement() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAndAccept(rca);

        // First update with nonce 1 — should succeed
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 60,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            });

        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));

        // Second update with nonce 1 again — should revert (expects 2)
        rcau.maxOngoingTokensPerSecond = 3 ether;
        rcau.nonce = 1;

        vm.expectRevert();
        vm.prank(operator);
        ram.offerAgreement(IRecurringCollector(address(recurringCollector)), OFFER_TYPE_UPDATE, abi.encode(rcau));
    }

    // ==================== Hash verification ====================

    function test_Accept_Revert_WhenHashMismatch() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeRCA(
            100 ether,
            1 ether,
            3600,
            uint64(block.timestamp + 365 days)
        );
        bytes16 agreementId = _offerAgreement(rca);

        vm.expectRevert();
        vm.prank(indexer);
        recurringCollector.accept(agreementId, bytes32(uint256(1)), bytes(""), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
