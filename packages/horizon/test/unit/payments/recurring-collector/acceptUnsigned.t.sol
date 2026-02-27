// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockContractApprover } from "./MockContractApprover.t.sol";

contract RecurringCollectorAcceptUnsignedTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockContractApprover) {
        return new MockContractApprover();
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
                    nonce: 1,
                    metadata: ""
                })
            );
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_AcceptUnsigned(FuzzyTestAccept calldata fuzzyTestAccept) public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        rca.payer = address(approver);

        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);

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
            uint64(block.timestamp),
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

    function test_AcceptUnsigned_Revert_WhenPayerNotContract() public {
        address eoa = makeAddr("eoa");
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(eoa);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorApproverNotContract.selector, eoa)
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenHashNotAuthorized() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        // Don't authorize the hash
        vm.expectRevert();
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenWrongMagicValue() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        approver.setOverrideReturnValue(bytes4(0xdeadbeef));

        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenNotDataService() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);

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
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        rca.payer = address(approver);

        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            agreementId,
            IRecurringCollector.AgreementState.Accepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    function test_AcceptUnsigned_Revert_WhenApproverReverts() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        approver.setShouldRevert(true);

        vm.expectRevert("MockContractApprover: forced revert");
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, "");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
