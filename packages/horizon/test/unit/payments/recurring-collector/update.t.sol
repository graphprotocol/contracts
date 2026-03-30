// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    REGISTERED,
    ACCEPTED,
    UPDATE,
    OFFER_TYPE_UPDATE
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

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
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;

        boundSkipCeil(unboundedUpdateSkip, type(uint64).max);
        rcau.deadline = uint64(bound(rcau.deadline, 0, block.timestamp - 1));

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.AgreementDeadlineElapsed.selector,
            block.timestamp,
            rcau.deadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
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

        // accept checks serviceProvider first — non-existent agreement has serviceProvider = address(0)
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.UnauthorizedServiceProvider.selector,
            rca.serviceProvider,
            address(0)
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, bytes32(0), bytes(""), 0);
    }

    function test_Update_Revert_WhenServiceProviderNotAuthorized(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        address notServiceProvider
    ) public {
        vm.assume(fuzzyTestUpdate.fuzzyTestAccept.rca.serviceProvider != notServiceProvider);
        vm.assume(notServiceProvider != _proxyAdmin);
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 1;

        // Step 1: Payer submits offerUpdate
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Step 2: Wrong caller tries to accept - should revert
        bytes32 pendingHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.UnauthorizedServiceProvider.selector,
            notServiceProvider,
            fuzzyTestUpdate.fuzzyTestAccept.rca.serviceProvider
        );
        vm.expectRevert(expectedErr);
        vm.prank(notServiceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);
    }

    function test_Update_Revert_WhenUnauthorizedPayer(
        FuzzyTestUpdate calldata fuzzyTestUpdate,
        address notPayer
    ) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        vm.assume(notPayer != acceptedRca.payer);

        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;

        vm.expectRevert(
            abi.encodeWithSelector(IRecurringCollector.UnauthorizedPayer.selector, notPayer, acceptedRca.payer)
        );
        vm.prank(notPayer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_Update_Revert_WhenMaxOngoingTokensOverflows(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 1;
        // maxOngoingTokensPerSecond * maxSecondsPerCollection overflows uint256
        rcau.maxOngoingTokensPerSecond = type(uint256).max;

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_Update_OK(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;
        // Don't use fuzzed nonce - use correct nonce for first update
        rcau.nonce = 1;

        // Step 1: Payer submits offerUpdate
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);

        // Step 2: Service provider accepts the update
        bytes32 pendingHash = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.AgreementUpdated(rcau.agreementId, pendingHash, REGISTERED | ACCEPTED | UPDATE);
        vm.prank(acceptedRca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash, bytes(""), 0);

        IRecurringCollector.AgreementData memory updatedAgreement = _recurringCollector.getAgreementData(agreementId);
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
        assertEq(rcau.nonce, updatedAgreement.updateNonce);
    }

    function test_Update_Revert_WhenInvalidNonce_TooLow(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 0; // Invalid: should be 1 for first update

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.InvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            0 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_Update_Revert_WhenInvalidNonce_TooHigh(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau.agreementId = agreementId;
        rcau.nonce = 5; // Invalid: should be 1 for first update

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.InvalidUpdateNonce.selector,
            rcau.agreementId,
            1, // expected
            5 // provided
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau), 0);
    }

    function test_Update_Revert_WhenReplayAttack(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau1.agreementId = agreementId;
        rcau1.nonce = 1;

        // First update succeeds (offerUpdate + accept)
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);
        bytes32 pendingHash1 = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(acceptedRca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash1, bytes(""), 0);

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
                minSecondsPayerCancellationNotice: 0,
                nonce: 2,
                metadata: rcau1.metadata
            });

        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);
        bytes32 pendingHash2 = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(acceptedRca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash2, bytes(""), 0);

        // Attempting to replay first update should fail (nonce check in offerUpdate)
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.InvalidUpdateNonce.selector,
            rcau1.agreementId,
            3, // expected (current nonce + 1)
            1 // provided (old nonce)
        );
        vm.expectRevert(expectedErr);
        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);
    }

    function test_Update_OK_NonceIncrementsCorrectly(FuzzyTestUpdate calldata fuzzyTestUpdate) public {
        (IRecurringCollector.RecurringCollectionAgreement memory acceptedRca, bytes16 agreementId) = _sensibleAccept(
            fuzzyTestUpdate.fuzzyTestAccept
        );

        // Initial nonce should be 0
        IRecurringCollector.AgreementData memory initialAgreement = _recurringCollector.getAgreementData(agreementId);
        assertEq(initialAgreement.updateNonce, 0);

        // First update with nonce 1
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau1 = _recurringCollectorHelper.sensibleRCAU(
            fuzzyTestUpdate.rcau,
            acceptedRca.payer
        );
        rcau1.agreementId = agreementId;
        rcau1.nonce = 1;

        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau1), 0);
        bytes32 pendingHash1 = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(acceptedRca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash1, bytes(""), 0);

        // Verify nonce incremented to 1
        IRecurringCollector.AgreementData memory updatedAgreement1 = _recurringCollector.getAgreementData(agreementId);
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
                minSecondsPayerCancellationNotice: 0,
                nonce: 2,
                metadata: rcau1.metadata
            });

        vm.prank(acceptedRca.payer);
        _recurringCollector.offer(OFFER_TYPE_UPDATE, abi.encode(rcau2), 0);
        bytes32 pendingHash2 = _recurringCollector.getAgreementVersionAt(agreementId, 1).versionHash;
        vm.prank(acceptedRca.serviceProvider);
        _recurringCollector.accept(agreementId, pendingHash2, bytes(""), 0);

        // Verify nonce incremented to 2
        IRecurringCollector.AgreementData memory updatedAgreement2 = _recurringCollector.getAgreementData(agreementId);
        assertEq(updatedAgreement2.updateNonce, 2);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
