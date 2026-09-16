// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Tests for validation branch coverage in RecurringCollector.accept().
contract RecurringCollectorAcceptValidationTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    uint256 internal constant SIGNER_KEY = 0xBEEF;

    function _makeValidRCA() internal returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        return
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: vm.addr(SIGNER_KEY),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            });
    }

    function _signAndAccept(IRecurringCollector.RecurringCollectionAgreement memory rca) internal {
        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== Zero address checks (L175) ====================

    function test_Accept_Revert_WhenDataServiceZero() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.dataService = address(0);

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);

        // dataService is zero, so msg.sender check (L173) will fail first because
        // we can't prank as address(0) and match. But the addresses-not-set check
        // fires after the caller check. Let's prank as address(0) to pass L173.
        vm.prank(address(0));
        vm.expectRevert(IRecurringCollector.RecurringCollectorAgreementAddressNotSet.selector);
        _recurringCollector.accept(rca, signature);
    }

    // Note: payer=0 is impractical to test directly because authorization
    // (L150) fails before the address check (L175). The zero-address branch
    // is covered by the dataService=0 and serviceProvider=0 tests.

    function test_Accept_Revert_WhenServiceProviderZero() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.serviceProvider = address(0);

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        vm.prank(rca.dataService);
        vm.expectRevert(IRecurringCollector.RecurringCollectorAgreementAddressNotSet.selector);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== endsAt validation ====================

    function test_Accept_Revert_WhenEndsAtNotAfterDeadline() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        rca.endsAt = rca.deadline; // endsAt == deadline, fails "endsAt > deadline"

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementEndsBeforeDeadline.selector,
                rca.deadline,
                rca.endsAt
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== Collection window validation (L548) ====================

    function test_Accept_Revert_WhenCollectionWindowTooSmall() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // min=600, max=1000 -> difference = 400 < MIN_SECONDS_COLLECTION_WINDOW (600)
        rca.minSecondsPerCollection = 600;
        rca.maxSecondsPerCollection = 1000;
        rca.endsAt = uint64(block.timestamp + 365 days);

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementInvalidCollectionWindow.selector,
                uint32(600), // MIN_SECONDS_COLLECTION_WINDOW
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    function test_Accept_Revert_WhenMaxEqualsMin() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // max == min -> fails "maxSecondsPerCollection > minSecondsPerCollection"
        rca.minSecondsPerCollection = 3600;
        rca.maxSecondsPerCollection = 3600;
        rca.endsAt = uint64(block.timestamp + 365 days);

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementInvalidCollectionWindow.selector,
                uint32(600), // MIN_SECONDS_COLLECTION_WINDOW
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== Duration validation (L560) ====================

    function test_Accept_Revert_WhenDurationTooShort() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // Need: endsAt - deadline >= minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW
        // Set duration just under the minimum
        uint32 minWindow = 600; // MIN_SECONDS_COLLECTION_WINDOW
        rca.minSecondsPerCollection = 600;
        rca.maxSecondsPerCollection = 600 + minWindow; // valid window
        rca.endsAt = rca.deadline + rca.minSecondsPerCollection + minWindow - 1; // 1 second too short

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorAgreementInvalidDuration.selector,
                rca.minSecondsPerCollection + minWindow,
                uint256(rca.endsAt - rca.deadline)
            )
        );
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== Caller authorization (L173) ====================

    function test_Accept_Revert_WhenCallerNotDataService() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        address wrongCaller = makeAddr("wrongCaller");
        vm.expectRevert(
            abi.encodeWithSelector(
                IRecurringCollector.RecurringCollectorUnauthorizedCaller.selector,
                wrongCaller,
                rca.dataService
            )
        );
        vm.prank(wrongCaller);
        _recurringCollector.accept(rca, signature);
    }

    // ==================== Overflow validation ====================

    function test_Accept_Revert_WhenMaxOngoingTokensOverflows() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // Set maxOngoingTokensPerSecond so that maxOngoingTokensPerSecond * maxSecondsPerCollection * 1024 overflows
        rca.maxOngoingTokensPerSecond = type(uint256).max / 1024; // overflow when multiplied by 3600 * 1024
        rca.maxSecondsPerCollection = 3600;

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.expectRevert(); // overflow panic
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    function test_Accept_OK_WhenMaxOngoingTokensAtBoundary() public {
        IRecurringCollector.RecurringCollectionAgreement memory rca = _makeValidRCA();
        // Set values at exactly the boundary that does not overflow
        rca.maxSecondsPerCollection = 3600;
        rca.maxOngoingTokensPerSecond = type(uint256).max / (uint256(3600) * 1024);
        // Ensure collection window is valid
        rca.minSecondsPerCollection = 600;

        _recurringCollectorHelper.authorizeSignerWithChecks(rca.payer, SIGNER_KEY);
        (, bytes memory signature) = _recurringCollectorHelper.generateSignedRCA(rca, SIGNER_KEY);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        // Should not revert
        vm.prank(rca.dataService);
        _recurringCollector.accept(rca, signature);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
