// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";
import { MockContractApprover } from "./MockContractApprover.t.sol";

/// @notice Tests that ECDSA and contract-approved paths can be mixed for accept and update.
contract RecurringCollectorMixedPathTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice ECDSA accept, then contract-approved update should fail (payer is EOA)
    function test_MixedPath_ECDSAAccept_UnsignedUpdate_RevertsForEOA() public {
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

        // Accept via ECDSA
        (, , bytes16 agreementId) = _authorizeAndAccept(rca, signerKey);

        // Try unsigned update — should revert because payer is an EOA
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                nonce: 1,
                metadata: ""
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorApproverNotContract.selector, payer)
        );
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    /// @notice Contract-approved accept, then ECDSA update should fail (no authorized signer)
    function test_MixedPath_UnsignedAccept_ECDSAUpdate_RevertsForUnauthorizedSigner() public {
        MockContractApprover approver = new MockContractApprover();

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
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via contract-approved path
        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Try ECDSA update with an unauthorized signer
        uint256 wrongKey = 0xDEAD;
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 200 ether,
                maxOngoingTokensPerSecond: 2 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                nonce: 1,
                metadata: ""
            })
        );

        (, bytes memory sig) = _recurringCollectorHelper.generateSignedRCAU(rcau, wrongKey);

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, sig);
    }

    /// @notice Contract-approved accept, then contract-approved update works
    function test_MixedPath_UnsignedAccept_UnsignedUpdate_OK() public {
        MockContractApprover approver = new MockContractApprover();

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
                nonce: 1,
                metadata: ""
            })
        );

        // Accept via contract-approved path
        bytes32 agreementHash = _recurringCollector.hashRCA(rca);
        approver.authorize(agreementHash);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        // Update via contract-approved path (use sensibleRCAU to stay in valid ranges)
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            IRecurringCollector.RecurringCollectionAgreementUpdate({
                agreementId: agreementId,
                deadline: 0,
                endsAt: uint64(block.timestamp + 730 days),
                maxInitialTokens: 50 ether,
                maxOngoingTokensPerSecond: 0.5 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 7200,
                nonce: 1,
                metadata: ""
            })
        );

        bytes32 updateHash = _recurringCollector.hashRCAU(rcau);
        approver.authorize(updateHash);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            rca.dataService,
            address(approver),
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

        // Verify updated terms
        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.maxOngoingTokensPerSecond, rcau.maxOngoingTokensPerSecond);
        assertEq(agreement.maxSecondsPerCollection, rcau.maxSecondsPerCollection);
        assertEq(agreement.updateNonce, 1);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
