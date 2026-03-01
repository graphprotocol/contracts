// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorUpdateTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Update_Revert_WhenUpdateElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        uint256 unboundedUpdateSkip
    ) public {
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rcau = _recurringCollectorHelper.sensibleRCAU(rcau);
        // Generate deterministic agreement ID
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        rcau.agreementId = agreementId;

        boundSkipCeil(unboundedUpdateSkip, type(uint64).max);
        rcau.deadline = uint64(bound(rcau.deadline, 0, block.timestamp - 1));
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_Revert_WhenNeverAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau
    ) public {
        rca = _recurringCollectorHelper.sensibleRCA(rca);
        rcau = _recurringCollectorHelper.sensibleRCAU(rcau);
        // Generate deterministic agreement ID
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        rcau.agreementId = agreementId;

        rcau.deadline = uint64(block.timestamp);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            rcau.agreementId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_Revert_WhenDataServiceNotAuthorized(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        address notDataService
    ) public {
        vm.assume(fuzzyTestUpdate.fuzzyTestAccept.rca.dataService != notDataService);
        (, uint256 signerKey, bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAUWithCorrectNonce(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            signedRCAU.rcau.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_Revert_WhenInvalidSigner(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        uint256 unboundedInvalidSignerKey
    ) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        uint256 invalidSignerKey = boundKey(unboundedInvalidSignerKey);
        vm.assume(signerKey != invalidSignerKey);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            invalidSignerKey
        );

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_OK(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        // Don't use fuzzed nonce - use correct nonce for first update
        rcau.nonce = 1;
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            accepted.rca.dataService,
            accepted.rca.payer,
            accepted.rca.serviceProvider,
            rcau.agreementId,
            uint64(block.timestamp),
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(rcau.endsAt, agreement.endsAt);
        assertEq(rcau.maxInitialTokens, agreement.maxInitialTokens);
        assertEq(rcau.maxOngoingTokensPerSecond, agreement.maxOngoingTokensPerSecond);
        assertEq(rcau.minSecondsPerCollection, agreement.minSecondsPerCollection);
        assertEq(rcau.maxSecondsPerCollection, agreement.maxSecondsPerCollection);
        assertEq(rcau.nonce, agreement.updateNonce);
    }

    function test_Update_Revert_WhenInvalidNonce_TooLow(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 0; // Invalid: should be 1 for first update

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            0 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_Revert_WhenInvalidNonce_TooHigh(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 5; // Invalid: should be 1 for first update

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            5 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU);
    }

    function test_Update_Revert_WhenReplayAttack(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau1.agreementId = agreementId;
        rcau1.nonce = 1;

        // First update succeeds
        IRecurringCollector.SignedRCAU memory signedRCAU1 = _recurringCollectorHelper.generateSignedRCAU(
            rcau1,
            signerKey
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU1);

        // Second update with different terms and nonce 2 succeeds
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = rcau1;
        rcau2.nonce = 2;
        rcau2.maxOngoingTokensPerSecond = rcau1.maxOngoingTokensPerSecond * 2; // Different terms

        IRecurringCollector.SignedRCAU memory signedRCAU2 = _recurringCollectorHelper.generateSignedRCAU(
            rcau2,
            signerKey
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU2);

        // Attempting to replay first update should fail
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau1.agreementId,
            3, // expected (current nonce + 1)
            1 // provided (old nonce)
        );
        vm.expectRevert(expectedErr);
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU1);
    }

    function test_Update_OK_NonceIncrementsCorrectly(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.SignedRCA memory accepted,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        // Initial nonce should be 0
        IRecurringCollector.AgreementData memory initialAgreement = _recurringCollector.getAgreement(agreementId);
        assertEq(initialAgreement.updateNonce, 0);

        // First update with nonce 1
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau1.agreementId = agreementId;
        rcau1.nonce = 1;

        IRecurringCollector.SignedRCAU memory signedRCAU1 = _recurringCollectorHelper.generateSignedRCAU(
            rcau1,
            signerKey
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU1);

        // Verify nonce incremented to 1
        IRecurringCollector.AgreementData memory updatedAgreement1 = _recurringCollector.getAgreement(agreementId);
        assertEq(updatedAgreement1.updateNonce, 1);

        // Second update with nonce 2
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = rcau1;
        rcau2.nonce = 2;
        rcau2.maxOngoingTokensPerSecond = rcau1.maxOngoingTokensPerSecond * 2; // Different terms

        IRecurringCollector.SignedRCAU memory signedRCAU2 = _recurringCollectorHelper.generateSignedRCAU(
            rcau2,
            signerKey
        );
        vm.prank(accepted.rca.dataService);
        _recurringCollector.update(signedRCAU2);

        // Verify nonce incremented to 2
        IRecurringCollector.AgreementData memory updatedAgreement2 = _recurringCollector.getAgreement(agreementId);
        assertEq(updatedAgreement2.updateNonce, 2);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
