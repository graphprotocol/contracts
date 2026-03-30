// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

contract RecurringCollectorUpdateUnsignedTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockAgreementOwner) {
        return new MockAgreementOwner();
    }

    /// @notice Helper to accept an agreement via the offer+accept path and return the ID
    function _acceptUnsigned(
        MockAgreementOwner approver,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Service provider accepts with stored hash
        bytes32 activeHash = _recurringCollector.getAgreementDetails(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        return agreementId;
    }

    function _makeSimpleRCA(address payer) internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
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
                    minSecondsPayerCancellationNotice: 0,
                    nonce: 1,
                    metadata: ""
                })
            );
    }

    function _makeSimpleRCAU(
        bytes16 agreementId,
        uint32 nonce
    ) internal view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return
            _recurringCollectorHelper.sensibleRCAU(
                IRecurringCollector.RecurringCollectionAgreementUpdate({
                    agreementId: agreementId,
                    deadline: 0,
                    endsAt: uint64(block.timestamp + 730 days),
                    maxInitialTokens: 200 ether,
                    maxOngoingTokensPerSecond: 2 ether,
                    minSecondsPerCollection: 600,
                    maxSecondsPerCollection: 7200,
                    conditions: 0,
                    minSecondsPayerCancellationNotice: 0,
                    nonce: nonce,
                    metadata: ""
                })
            );
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_UpdateUnsigned() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Payer calls offerUpdate
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Data service accepts update with stored hash
        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(agreementId, pendingHash, REGISTERED | ACCEPTED | UPDATE);

        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        IRecurringCollector.AgreementData memory updated = _recurringCollector.getAgreementData(agreementId);
        {
            (, bytes memory activeOfferData) = _recurringCollector.getAgreementOfferAt(agreementId, 0);
            IRecurringCollector.RecurringCollectionAgreementUpdate memory activeRcau = abi.decode(
                activeOfferData,
                (IRecurringCollector.RecurringCollectionAgreementUpdate)
            );
            assertEq(rcau.endsAt, activeRcau.endsAt);
            assertEq(rcau.maxInitialTokens, activeRcau.maxInitialTokens);
            assertEq(rcau.maxOngoingTokensPerSecond, activeRcau.maxOngoingTokensPerSecond);
            assertEq(rcau.minSecondsPerCollection, activeRcau.minSecondsPerCollection);
            assertEq(rcau.maxSecondsPerCollection, activeRcau.maxSecondsPerCollection);
        }
        assertEq(rcau.nonce, updated.updateNonce);
    }

    function test_UpdateUnsigned_Revert_WhenHashNotAuthorized() public {
        // With the offer/accept update path, the hash is stored by offerUpdate().
        // This test verifies that accept() with a mismatched hash fails.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Payer calls offerUpdate
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        // Data service tries to accept with wrong hash
        bytes32 badHash = bytes32(uint256(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementHashMismatch.selector,
                agreementId,
                pendingHash,
                badHash
            )
        );
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, badHash, bytes(""), 0);
    }

    function test_UpdateUnsigned_Revert_WhenWrongMagicValue() public {
        // With offer/accept, there is no approveAgreement callback. Instead, test
        // that a non-payer cannot call offerUpdate.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        address notPayer = makeAddr("notPayer");
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.UnauthorizedPayer.selector, notPayer, address(approver))
        );
        vm.prank(notPayer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_UpdateUnsigned_Revert_WhenNotDataService() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Payer calls offerUpdate
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        address notServiceProvider = makeAddr("notServiceProvider");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.UnauthorizedServiceProvider.selector,
                notServiceProvider,
                rca.serviceProvider
            )
        );
        vm.prank(notServiceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);
    }

    function test_UpdateUnsigned_Revert_WhenNotAccepted() public {
        // Don't accept — just try to accept a non-existent agreement
        bytes16 fakeId = bytes16(keccak256("fake"));
        address caller = makeAddr("ds");

        // accept checks serviceProvider first — non-existent agreement has serviceProvider = address(0)
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.UnauthorizedServiceProvider.selector,
            caller,
            address(0)
        );
        vm.expectRevert(expectedErr);
        vm.prank(caller);
        _recurringCollector.accept(fakeId, bytes32(0), bytes(""), 0);
    }

    function test_UpdateUnsigned_Revert_WhenInvalidNonce() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        // Use wrong nonce (0 instead of 1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 0);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.InvalidUpdateNonce.selector,
            agreementId,
            1, // expected
            0 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_UpdateUnsigned_Revert_WhenApproverReverts() public {
        // With the offer/accept path, the "approver reverts" concept translates to
        // accept with a wrong hash.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Payer calls offerUpdate
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes32 pendingHash = _recurringCollector.getAgreementDetails(agreementId, 1).versionHash;

        // Data service accepts with a wrong hash
        bytes32 wrongHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementHashMismatch.selector,
                agreementId,
                pendingHash,
                wrongHash
            )
        );
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, wrongHash, bytes(""), 0);
    }

    function test_UpdateUnsigned_Revert_WhenDeadlineElapsed() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Set the update deadline in the past
        rcau.deadline = uint64(block.timestamp - 1);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementDeadlineElapsed.selector,
            block.timestamp,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
