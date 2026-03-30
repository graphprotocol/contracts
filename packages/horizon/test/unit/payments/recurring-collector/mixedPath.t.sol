// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    WITH_NOTICE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

/// @notice Tests the contract-approved offer+accept path for accept and update.
contract RecurringCollectorMixedPathTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice Contract-approved accept, then contract-approved update works
    function test_MixedPath_UnsignedAccept_UnsignedUpdate_OK() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via offer+accept path
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        // Update via offerUpdate+accept path
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 50 ether,
                maxOngoingTokensPerSecond: 0.5 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                minSecondsPayerCancellationNotice: 0,
                nonce: 1,
                metadata: ""
            })
        );

        // Payer calls offerUpdate
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Data service accepts update with stored hash
        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(agreementId, pendingHash, REGISTERED | ACCEPTED | UPDATE);

        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // Verify updated terms
        IRecurringCollector.AgreementData memory finalAgreement = _recurringCollector.getAgreementData(agreementId);
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(activeRcau.maxOngoingTokensPerSecond, rcau.maxOngoingTokensPerSecond);
            assertEq(activeRcau.maxSecondsPerCollection, rcau.maxSecondsPerCollection);
        }
        assertEq(finalAgreement.updateNonce, 1);
    }

    /// @notice WITH_NOTICE + deadline=0 pending terms can be manually accepted
    function test_MixedPath_WithNotice_DeadlineZero_ManualAccept() public {
        MockAgreementOwner approver = new MockAgreementOwner();

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(approver),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                minSecondsPayerCancellationNotice: 60,
                nonce: 1,
                metadata: ""
            })
        );

        // Offer + accept initial terms
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        // Payer offers update with WITH_NOTICE and deadline=0
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 50 ether,
                maxOngoingTokensPerSecond: 0.5 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                conditions: 0,
                minSecondsPayerCancellationNotice: 60,
                nonce: 1,
                metadata: ""
            });

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), WITH_NOTICE);

        // Service provider manually accepts the deadline=0 pending terms
        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        // Verify the update was accepted and agreement is active
        IRecurringCollector.AgreementData memory data = _recurringCollector.getAgreementData(agreementId);
        assertEq(data.updateNonce, 1);
        assertEq(data.state, REGISTERED | ACCEPTED | UPDATE);
        assertEq(data.collectableUntil, rcau.endsAt);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
