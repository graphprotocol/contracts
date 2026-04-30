// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW, OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

contract RecurringCollectorUpdateUnsignedTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockAgreementOwner) {
        return new MockAgreementOwner();
    }

    /// @notice Helper to accept an agreement via the unsigned path and return the ID
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

        // Store the update offer
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            rca.dataService,
            rca.payer,
            rca.serviceProvider,
            agreementId,
            uint64(block.timestamp),
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );

        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(rcau.endsAt, agreement.endsAt);
        assertEq(rcau.maxInitialTokens, agreement.maxInitialTokens);
        assertEq(rcau.maxOngoingTokensPerSecond, agreement.maxOngoingTokensPerSecond);
        assertEq(rcau.minSecondsPerCollection, agreement.minSecondsPerCollection);
        assertEq(rcau.maxSecondsPerCollection, agreement.maxSecondsPerCollection);
        assertEq(rcau.nonce, agreement.updateNonce);
    }

    function test_UpdateUnsigned_Revert_WhenHashNotAuthorized() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Don't authorize the update hash — approver returns bytes4(0), caller rejects
        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenWrongMagicValue() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // With stored offers, "wrong magic value" maps to "no matching offer stored"
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenNotDataService() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        address notDataService = makeAddr("notDataService");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
                agreementId,
                notDataService
            )
        );
        vm.prank(notDataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenNotAccepted() public {
        // Don't accept — just try to update a non-existent agreement
        bytes16 fakeId = bytes16(keccak256("fake"));
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(fakeId, 1);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            fakeId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(makeAddr("ds"));
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenInvalidNonce() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        // Use wrong nonce (0 instead of 1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 0);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            agreementId,
            1, // expected
            0 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenNoOfferStored() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // No offer stored — should revert with InvalidSigner
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenDeadlineElapsed() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Set the update deadline in the past
        rcau.deadline = uint64(block.timestamp - 1);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
