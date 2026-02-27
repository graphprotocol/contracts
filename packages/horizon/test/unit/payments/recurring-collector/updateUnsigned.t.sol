// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockContractApprover } from "./MockContractApprover.t.sol";

contract RecurringCollectorUpdateUnsignedTest is RecurringCollectorSharedTest {
    function _newApprover() internal returns (MockContractApprover) {
        return new MockContractApprover();
    }

    /// @notice Helper to accept an agreement via the unsigned path and return the ID
    function _acceptUnsigned(
        MockContractApprover approver,
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) internal returns (bytes16) {
        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);

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
                    nonce: nonce,
                    metadata: ""
                })
            );
    }

    /* solhint-disable graph/func-name-mixedcase */

    function test_UpdateUnsigned() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Authorize the update hash
        bytes32 updateHash = _recurringCollector.hashRCAU(rcau);
        approver.authorize(updateHash);

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

    function test_UpdateUnsigned_Revert_WhenPayerNotContract() public {
        // Use the signed accept path to create an agreement with an EOA payer,
        // then attempt updateUnsigned which should fail because payer isn't a contract
        uint256 signerKey = 0xA11CE;
        address payer = vm.addr(signerKey);
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
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

        // Accept via signed path
        _recurringCollectorHelper.authorizeSignerWithChecks(payer, signerKey);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, signature);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorApproverNotContract.selector, payer)
        );
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenHashNotAuthorized() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        // Don't authorize the update hash — approver returns bytes4(0), caller rejects
        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenWrongMagicValue() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        approver.setOverrideReturnValue(bytes4(0xdeadbeef));

        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.RecurringCollectorInvalidSigner.selector));
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_UpdateUnsigned_Revert_WhenNotDataService() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        bytes32 updateHash = _recurringCollector.hashRCAU(rcau);
        approver.authorize(updateHash);

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
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        // Use wrong nonce (0 instead of 1)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 0);

        bytes32 updateHash = _recurringCollector.hashRCAU(rcau);
        approver.authorize(updateHash);

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

    function test_UpdateUnsigned_Revert_WhenApproverReverts() public {
        MockContractApprover approver = _newApprover();
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeSimpleRCA(address(approver));

        bytes16 agreementId = _acceptUnsigned(approver, rca);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _makeSimpleRCAU(agreementId, 1);

        approver.setShouldRevert(true);

        vm.expectRevert("MockContractApprover: forced revert");
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
