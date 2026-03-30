// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    OFFER_TYPE_NEW
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

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
                    minSecondsPayerCancellationNotice: 0,
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

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        bytes16 expectedId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        assertEq(agreementId, expectedId);

        // Data service accepts with stored hash
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(expectedId, activeHash, REGISTERED | ACCEPTED);

        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        IRecurringCollector.AgreementData memory accepted = _recurringCollector.getAgreementData(agreementId);
        assertEq(accepted.state, REGISTERED | ACCEPTED);
        assertEq(accepted.payer, address(approver));
        assertEq(accepted.serviceProvider, rca.serviceProvider);
        assertEq(accepted.dataService, rca.dataService);
        assertEq(accepted.state, REGISTERED | ACCEPTED);
    }

    function test_AcceptUnsigned_OK_WhenPayerIsEOA() public {
        address eoa = makeAddr("eoa");
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(eoa);

        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(eoa);
        IRecurringCollector.OfferResult memory result = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        assertTrue(result.agreementId != bytes16(0));
    }

    function test_AcceptUnsigned_Revert_WhenWrongMagicValue() public {
        // With the offer/accept path, the "wrong magic value" concept no longer applies
        // since there is no approveAgreement callback. Instead, test that a non-payer
        // cannot call offer.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        // Someone other than payer tries to call offer
        address notPayer = makeAddr("notPayer");
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.UnauthorizedPayer.selector, notPayer, address(approver))
        );
        vm.prank(notPayer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_AcceptUnsigned_Revert_WhenNotDataService() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;

        address notServiceProvider = makeAddr("notServiceProvider");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.UnauthorizedServiceProvider.selector,
                notServiceProvider,
                rca.serviceProvider
            )
        );
        vm.prank(notServiceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    function test_AcceptUnsigned_Revert_WhenAlreadyAccepted(FuzzyTestAccept calldata fuzzyTestAccept) public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        rca.payer = address(approver);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Service provider accepts
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);

        // Second accept should fail — no pending update, so terms are empty
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementTermsEmpty.selector,
            agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    function test_AcceptUnsigned_Revert_WhenApproverReverts() public {
        // With the offer/accept path, the payer calls offer() directly.
        // "Approver reverts" doesn't apply the same way. Instead, test that
        // accept() with a wrong hash reverts.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;

        // Accept with wrong hash should revert
        bytes32 wrongHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementHashMismatch.selector,
                agreementId,
                activeHash,
                wrongHash
            )
        );
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, wrongHash, bytes(""), 0);
    }

    function test_AcceptUnsigned_Revert_WhenEndsAtElapsed() public {
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));
        // Set deadline far in the future so the endsAt check fires first
        rca.deadline = type(uint64).max;

        // Advance time past endsAt so the offer is rejected
        vm.warp(rca.endsAt + 1);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementInvalidCollectionWindow.selector,
            IRecurringCollector.InvalidCollectionWindowReason.ElapsedEndsAt,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(address(approver));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_AcceptUnsigned_Revert_WhenHashNotAuthorized() public {
        // With the offer/accept path, the hash is stored by offer().
        // There is no separate "authorization" step. This test now verifies that
        // accept() with a mismatched hash fails.
        MockAgreementOwner approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Payer calls offer
        vm.prank(address(approver));
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;

        // Try accept with a completely wrong hash
        bytes32 badHash = bytes32(uint256(0xdead));
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.AgreementHashMismatch.selector, agreementId, activeHash, badHash)
        );
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, badHash, bytes(""), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
