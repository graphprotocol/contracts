// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Tests for validation branch coverage in RecurringCollector.accept().
contract RecurringCollectorAcceptValidationTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function _makeValidRCA() internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: makeAddr("payer"),
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
            });
    }

    function _offerAndAccept(IRecurringCollector.RecurringCollectionAgreement memory rca) internal {
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        // Step 1: Payer submits offer
        vm.prank(rca.payer);
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        // Step 2: Service provider accepts
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    // ==================== Zero address checks (L175) ====================

    function test_Accept_Revert_WhenDataServiceZero() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.dataService = address(0);

        // offer() checks addresses via _storeOffer
        vm.expectRevert(IRecurringCollector.AgreementAddressNotSet.selector);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // Note: payer=0 is impractical to test directly because authorization
    // (L150) fails before the address check (L175). The zero-address branch
    // is covered by the dataService=0 and serviceProvider=0 tests.

    function test_Accept_Revert_WhenServiceProviderZero() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.serviceProvider = address(0);

        // offer() checks addresses via _storeOffer
        vm.expectRevert(IRecurringCollector.AgreementAddressNotSet.selector);
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ==================== endsAt validation (L545) ====================

    function test_Accept_Revert_WhenEndsAtInPast() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.endsAt = uint64(block.timestamp); // endsAt == now, fails "endsAt > block.timestamp"

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // offer() validates endsAt via _storeOffer
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementInvalidCollectionWindow.selector,
                IRecurringCollector.InvalidCollectionWindowReason.ElapsedEndsAt,
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ==================== Collection window validation (L548) ====================

    function test_Accept_Revert_WhenCollectionWindowTooSmall() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // min=600, max=1000 -> difference = 400 < MIN_SECONDS_COLLECTION_WINDOW (600)
        rca.minSecondsPerCollection = 600;
        rca.maxSecondsPerCollection = 1000;
        rca.endsAt = uint64(block.timestamp + 365 days);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // offer() validates collection window via _storeOffer
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementInvalidCollectionWindow.selector,
                IRecurringCollector.InvalidCollectionWindowReason.InvalidWindow,
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_Accept_Revert_WhenMaxEqualsMin() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // max == min -> fails "maxSecondsPerCollection > minSecondsPerCollection"
        rca.minSecondsPerCollection = 3600;
        rca.maxSecondsPerCollection = 3600;
        rca.endsAt = uint64(block.timestamp + 365 days);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // offer() validates collection window via _storeOffer
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementInvalidCollectionWindow.selector,
                IRecurringCollector.InvalidCollectionWindowReason.InvalidWindow,
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ==================== Duration validation (L560) ====================

    function test_Accept_Revert_WhenDurationTooShort() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // Need: endsAt - now >= minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW
        // Set duration just under the minimum
        uint32 minWindow = _recurringCollector.MIN_SECONDS_COLLECTION_WINDOW();
        rca.minSecondsPerCollection = 600;
        rca.maxSecondsPerCollection = 600 + minWindow; // valid window
        rca.endsAt = uint64(block.timestamp + rca.minSecondsPerCollection + minWindow - 1); // 1 second too short

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // offer() validates duration via _storeOffer
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.AgreementInvalidCollectionWindow.selector,
                IRecurringCollector.InvalidCollectionWindowReason.InsufficientDuration,
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ==================== Overflow validation (maxOngoingTokensPerSecond * maxSecondsPerCollection) ====================

    function test_Offer_Revert_WhenMaxOngoingTokensOverflows() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // maxOngoingTokensPerSecond * maxSecondsPerCollection overflows uint256
        rca.maxOngoingTokensPerSecond = type(uint256).max;
        rca.maxSecondsPerCollection = 3600;

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    function test_Offer_OK_WhenMaxOngoingTokensAtBoundary() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // Largest value that does not overflow: type(uint256).max / maxSecondsPerCollection
        rca.maxOngoingTokensPerSecond = type(uint256).max / uint256(rca.maxSecondsPerCollection);

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Should succeed — product fits in uint256
        vm.prank(rca.payer);
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
    }

    // ==================== Caller authorization (L173) ====================

    function test_Accept_Revert_WhenCallerNotServiceProvider() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();

        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Step 1: Payer submits offer
        vm.prank(rca.payer);
        bytes16 agreementId = _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0).agreementId;
        bytes32 activeHash = _recurringCollector.getAgreementVersionAt(agreementId, 0).versionHash;

        // Step 2: Wrong caller tries to accept - should revert
        address wrongCaller = makeAddr("wrongCaller");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.UnauthorizedServiceProvider.selector,
                wrongCaller,
                rca.serviceProvider
            )
        );
        vm.prank(wrongCaller);
        _recurringCollector.accept(agreementId, activeHash, bytes(""), 0);
    }

    // ==================== Empty pending terms (L706) ====================

    function test_Accept_Revert_WhenPendingTermsEmpty() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();

        // Offer and accept to reach REGISTERED | ACCEPTED state
        _offerAndAccept(rca);
        bytes16 agreementId = _recurringCollector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        // No update was offered so pendingTerms.hash == bytes32(0).
        // Attempting to accept pending terms with versionHash = 0 should revert
        // with an explicit empty-terms guard, not rely on the deadline check.
        vm.expectRevert(abi.encodeWithSelector(IRecurringCollector.AgreementTermsEmpty.selector, agreementId));
        vm.prank(rca.serviceProvider);
        _recurringCollector.accept(agreementId, bytes32(0), bytes(""), 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
