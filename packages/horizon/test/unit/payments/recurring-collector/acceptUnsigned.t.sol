// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockAgreementOwner } from "./MockAgreementOwner.t.sol";

contract RecurringCollectorAcceptUnsignedTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockAgreementOwner) {
        return new MockAgreementOwner();
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

    /* solhint-disable graph/func-name-mixedcase */

    function test_AcceptUnsigned(FuzzyTestAccept calldata fuzzyTestAccept) public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        rca.payer = address(approver);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        bytes16 expectedId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementAccepted(
            rca.dataService,
            rca.payer,
            rca.serviceProvider,
            expectedId,
            rca.endsAt,
            rca.maxInitialTokens,
            rca.maxOngoingTokensPerSecond,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        assertEq(agreementId, expectedId);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(uint8(agreement.state), uint8(IRecurringCollector.AgreementState.Accepted));
        assertEq(agreement.payer, address(approver));
        assertEq(agreement.serviceProvider, rca.serviceProvider);
        assertEq(agreement.dataService, rca.dataService);
    }

    function test_AcceptUnsigned_Revert_WhenNoOfferStored() public {
        address eoa = makeAddr("eoa");
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(eoa);

        // No offer stored — stored-hash lookup fails
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenHashNotAuthorized() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        // Don't store an offer — should revert
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenWrongMagicValue() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        // With stored offers, "wrong magic value" maps to "no matching offer stored"
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenNotDataService() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        address notDataService = makeAddr("notDataService");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorUnauthorizedCaller.selector,
                notDataService,
                rca.dataService
            )
        );
        vm.prank(notDataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        rca.payer = address(approver);

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Stored offer persists, so authorization passes but state check fails
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
                agreementId,
                IRecurringCollector.AgreementState.Accepted
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenDeadlineElapsed() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);

        // Advance time past the deadline
        vm.warp(rca.deadline + 1);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            rca.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
