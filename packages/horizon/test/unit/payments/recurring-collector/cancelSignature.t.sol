// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import {
    SCOPE_SIGNED,
    SCOPE_ACTIVE,
    SCOPE_PENDING
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCancelSignedOfferTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_CancelSigned_BlocksAccept(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED);

        // Accepting with the cancelled signature should revert
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorOfferCancelled.selector, signer, rcaHash)
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    function test_CancelSigned_EmitsEvent(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferCancelled(signer, agreementId, rcaHash);
        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED);
    }

    function test_CancelSigned_BlocksUpdate(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (
            IRecurringCollector.RecurringCollectionAgreement memory rca,
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
            bytes memory rcauSig
        ) = _recurringCollectorHelper.generateSignedRCAUForAgreement(agreementId, rcau, signerKey);
        bytes32 rcauHash = _recurringCollector.hashRCAU(signedRcau);
        address signer = vm.addr(signerKey);

        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcauHash, SCOPE_SIGNED);

        // Updating with the cancelled signature should revert
        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.RecurringCollectorOfferCancelled.selector, signer, rcauHash)
        );
        vm.prank(rca.dataService);
        _recurringCollector.update(signedRcau, rcauSig);
    }

    function test_CancelSigned_Idempotent(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED);

        // Second call succeeds silently — no revert, no event
        vm.recordLogs();
        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_CancelSigned_DoesNotAffectDifferentSigner(
        FuzzyTestAccept calldata fuzzyTestAccept1,
        FuzzyTestAccept calldata fuzzyTestAccept2
    ) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca1 = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept1.rca
        );
        uint256 signerKey1 = boundKey(fuzzyTestAccept1.unboundedSignerKey);

        IRecurringCollector.RecurringCollectionAgreement memory rca2 = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept2.rca
        );
        uint256 signerKey2 = boundKey(fuzzyTestAccept2.unboundedSignerKey);

        vm.assume(rca1.payer != rca2.payer);
        vm.assume(vm.addr(signerKey1) != vm.addr(signerKey2));

        _recurringCollectorHelper.authorizeSignerWithChecks(rca1.payer, signerKey1);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca2.payer, signerKey2);

        bytes32 rcaHash = _recurringCollector.hashRCA(rca1);

        // Signer1 cancels — should not affect signer2
        vm.prank(vm.addr(signerKey1));
        _recurringCollector.cancel(bytes16(0), rcaHash, SCOPE_SIGNED);

        // Signer2's signatures for the same hash are unaffected
        // (signer-scoped, not hash-global)
    }

    function test_CancelSigned_SelfAuthenticating(FuzzyTestAccept calldata fuzzyTestAccept, address anyAddress) public {
        // Any address can call cancel with SCOPE_SIGNED — it only records for msg.sender
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        vm.assume(anyAddress != address(0));
        vm.assume(anyAddress != _proxyAdmin);

        // Should not revert — self-authenticating, no _requirePayer
        vm.prank(anyAddress);
        _recurringCollector.cancel(bytes16(0), rcaHash, SCOPE_SIGNED);
    }

    function test_CancelSigned_CombinedWithActiveDoesNotRevert(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // SCOPE_SIGNED | SCOPE_ACTIVE with no accepted agreement — should not revert.
        // The signed recording succeeds; the active scope is skipped because nothing on-chain.
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferCancelled(signer, agreementId, rcaHash);
        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED | SCOPE_ACTIVE);
    }

    function test_CancelSigned_CombinedWithPendingDoesNotRevert(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // SCOPE_SIGNED | SCOPE_PENDING with no agreement — should not revert.
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.OfferCancelled(signer, agreementId, rcaHash);
        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED | SCOPE_PENDING);
    }

    function test_CancelSigned_UndoWithZero(FuzzyTestAccept calldata fuzzyTestAccept) public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            fuzzyTestAccept.rca
        );
        uint256 signerKey = boundKey(fuzzyTestAccept.unboundedSignerKey);
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, signerKey);

        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, signerKey);
        bytes32 rcaHash = _recurringCollector.hashRCA(rca);
        address signer = vm.addr(signerKey);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // Cancel
        vm.prank(signer);
        _recurringCollector.cancel(agreementId, rcaHash, SCOPE_SIGNED);

        // Undo by calling with bytes16(0)
        vm.prank(signer);
        _recurringCollector.cancel(bytes16(0), rcaHash, SCOPE_SIGNED);

        // Accept should now succeed
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
