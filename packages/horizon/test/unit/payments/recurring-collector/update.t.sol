// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { OFFER_TYPE_UPDATE } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorUpdateTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Update_Revert_WhenUpdateElapsed(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        uint256 unboundedUpdateSkip
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        boundSkipCeil(unboundedUpdateSkip, type(uint64).max);
        rcau.deadline = uint64(bound(rcau.deadline, 0, block.timestamp - 1));

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementDeadlineElapsed.selector,
            block.timestamp,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);
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

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementIncorrectState.selector,
            rcau.agreementId,
            IRecurringCollector.AgreementState.NotAccepted
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.update(rcau, "");
    }

    function test_Update_Revert_WhenDataServiceNotAuthorized(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        address notDataService
    ) public {
        vm.assume(fuzzyTestUpdate.fuzzyTestAccept.rca.dataService != notDataService);
        vm.assume(notDataService != _proxyAdmin);
        (, , uint256 signerKey, bytes16 agreementId) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAUWithCorrectNonce(rcau, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            rcau.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.update(rcau, signature);
    }

    function test_Update_Revert_WhenInvalidSigner(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        uint256 unboundedInvalidSignerKey
    ) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            ,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        uint256 signerKey = boundKey(fuzzyTestUpdate.fuzzyTestAccept.unboundedSignerKey);
        uint256 invalidSignerKey = boundKey(unboundedInvalidSignerKey);
        vm.assume(signerKey != invalidSignerKey);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, invalidSignerKey);

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);
    }

    function test_Update_OK(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        // Don't use fuzzed nonce - use correct nonce for first update
        rcau.nonce = 1;
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            acceptedRca.dataService,
            acceptedRca.payer,
            acceptedRca.serviceProvider,
            rcau.agreementId,
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(agreementId);
        assertEq(agreement.activeTermsHash, _recurringCollector.hashRCAU(rcau));
        assertEq(rcau.nonce, agreement.updateNonce);
    }

    function test_Update_Revert_WhenInvalidNonce_TooLow(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 0; // Invalid: should be 1 for first update

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            0 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);
    }

    function test_Update_Revert_WhenInvalidNonce_TooHigh(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 5; // Invalid: should be 1 for first update

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            5 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);
    }

    function test_Update_Revert_WhenReplayAttack(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau1.agreementId = agreementId;
        rcau1.nonce = 1;

        // First update succeeds
        (, bytes memory signature1) = _recurringCollectorHelper.generateSignedRCAU(rcau1, signerKey);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau1, signature1);

        // Second update with different terms and nonce 2 succeeds
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: rcau1.agreementId,
                deadline: rcau1.deadline,
                endsAt: rcau1.endsAt,
                maxInitialTokens: rcau1.maxInitialTokens,
                maxOngoingTokensPerSecond: rcau1.maxOngoingTokensPerSecond * 2, // Different terms
                minSecondsPerCollection: rcau1.minSecondsPerCollection,
                maxSecondsPerCollection: rcau1.maxSecondsPerCollection,
                conditions: 0,
                nonce: 2,
                metadata: rcau1.metadata
            });

        (, bytes memory signature2) = _recurringCollectorHelper.generateSignedRCAU(rcau2, signerKey);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau2, signature2);

        // Attempting to replay first update should fail
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidUpdateNonce.selector,
            rcau1.agreementId,
            3, // expected (current nonce + 1)
            1 // provided (old nonce)
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau1, signature1);
    }

    function test_Update_OK_NonceIncrementsCorrectly(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
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

        (, bytes memory signature1) = _recurringCollectorHelper.generateSignedRCAU(rcau1, signerKey);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau1, signature1);

        // Verify nonce incremented to 1
        IRecurringCollector.AgreementData memory updatedAgreement1 = _recurringCollector.getAgreement(agreementId);
        assertEq(updatedAgreement1.updateNonce, 1);

        // Second update with nonce 2
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau2 = IRecurringCollector
            .RecurringCollectionAgreementUpdate({
                agreementId: rcau1.agreementId,
                deadline: rcau1.deadline,
                endsAt: rcau1.endsAt,
                maxInitialTokens: rcau1.maxInitialTokens,
                maxOngoingTokensPerSecond: rcau1.maxOngoingTokensPerSecond * 2, // Different terms
                minSecondsPerCollection: rcau1.minSecondsPerCollection,
                maxSecondsPerCollection: rcau1.maxSecondsPerCollection,
                conditions: 0,
                nonce: 2,
                metadata: rcau1.metadata
            });

        (, bytes memory signature2) = _recurringCollectorHelper.generateSignedRCAU(rcau2, signerKey);
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau2, signature2);

        // Verify nonce incremented to 2
        IRecurringCollector.AgreementData memory updatedAgreement2 = _recurringCollector.getAgreement(agreementId);
        assertEq(updatedAgreement2.updateNonce, 2);
    }

    function test_Update_Idempotent_WhenAlreadyAtActiveHash(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 1;
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCAU(rcau, signerKey);

        // First update consumes nonce 1 and sets activeTermsHash = hash(rcau).
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);

        IRecurringCollector.AgreementData memory afterFirst = _recurringCollector.getAgreement(agreementId);
        assertEq(afterFirst.updateNonce, 1, "nonce advanced to 1 after first update");

        // Re-submitting the same RCAU is a no-op — nonce does NOT advance, no event, no revert.
        vm.recordLogs();
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(rcau, signature);
        assertEq(vm.getRecordedLogs().length, 0, "no event emitted on idempotent re-update");

        IRecurringCollector.AgreementData memory afterSecond = _recurringCollector.getAgreement(agreementId);
        assertEq(afterSecond.updateNonce, 1, "nonce unchanged on idempotent re-update");
        assertEq(afterSecond.activeTermsHash, afterFirst.activeTermsHash, "activeTermsHash unchanged");
    }

    /// @notice Direct-apply update (no prior offer(UPDATE) that staged the RCAU as pending) writes
    /// new terms via _validateAndStoreTerms, which must emit OfferStored. AgreementUpdated follows.
    function test_Update_EmitsOfferStored_WhenDirectApplyFreshTerms(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory acceptedRca,
            ,
            uint256 signerKey,
            bytes16 agreementId
        ) = _sensibleAuthorizeAndAccept(fuzzyTestUpdate.fuzzyTestAccept);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau
        );
        rcau.agreementId = agreementId;

        (
            IRecurringCollector.RecurringCollectionAgreementUpdate memory signedRcau,
            bytes memory signature
        ) = _recurringCollectorHelper.generateSignedRCAUForAgreement(agreementId, rcau, signerKey);
        bytes32 rcauHash = _recurringCollector.hashRCAU(signedRcau);

        // Pre-condition: no pending offer staged, so update() takes the direct-apply branch.
        assertEq(
            _recurringCollector.getAgreement(agreementId).pendingTermsHash,
            bytes32(0),
            "no pending before direct-apply"
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferStored(agreementId, acceptedRca.payer, OFFER_TYPE_UPDATE, rcauHash);
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(
            acceptedRca.dataService,
            acceptedRca.payer,
            acceptedRca.serviceProvider,
            agreementId,
            signedRcau.endsAt,
            signedRcau.maxInitialTokens,
            signedRcau.maxOngoingTokensPerSecond,
            signedRcau.minSecondsPerCollection,
            signedRcau.maxSecondsPerCollection
        );
        vm.prank(acceptedRca.dataService);
        _recurringCollector.update(signedRcau, signature);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
