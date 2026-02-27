// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Vm } from "forge-std/Vm.sol";

import { IRewardsEligibilityEvents } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibilityEvents.sol";

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Tests for operator-only configuration functions.
contract RewardsEligibilityOracleOperatorFunctionsTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    function setUp() public override {
        super.setUp();
        _setupOperatorRole();
    }

    // ==================== setEligibilityPeriod ====================

    function test_SetEligibilityPeriod() public {
        uint256 newPeriod = 30 days;
        vm.prank(operator);
        assertTrue(oracle.setEligibilityPeriod(newPeriod));
        assertEq(oracle.getEligibilityPeriod(), newPeriod);
    }

    function test_SetEligibilityPeriod_EmitsEvent() public {
        uint256 newPeriod = 30 days;
        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.EligibilityPeriodUpdated(DEFAULT_ELIGIBILITY_PERIOD, newPeriod);
        vm.prank(operator);
        oracle.setEligibilityPeriod(newPeriod);
    }

    function test_SetEligibilityPeriod_Idempotent_NoEvent() public {
        vm.prank(operator);
        assertTrue(oracle.setEligibilityPeriod(DEFAULT_ELIGIBILITY_PERIOD));

        // Verify no event emitted
        vm.recordLogs();
        vm.prank(operator);
        oracle.setEligibilityPeriod(DEFAULT_ELIGIBILITY_PERIOD);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    // ==================== setOracleUpdateTimeout ====================

    function test_SetOracleUpdateTimeout() public {
        uint256 newTimeout = 60 days;
        vm.prank(operator);
        assertTrue(oracle.setOracleUpdateTimeout(newTimeout));
        assertEq(oracle.getOracleUpdateTimeout(), newTimeout);
    }

    function test_SetOracleUpdateTimeout_EmitsEvent() public {
        uint256 newTimeout = 60 days;
        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.OracleUpdateTimeoutUpdated(DEFAULT_ORACLE_TIMEOUT, newTimeout);
        vm.prank(operator);
        oracle.setOracleUpdateTimeout(newTimeout);
    }

    function test_SetOracleUpdateTimeout_Idempotent_NoEvent() public {
        vm.recordLogs();
        vm.prank(operator);
        oracle.setOracleUpdateTimeout(DEFAULT_ORACLE_TIMEOUT);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    // ==================== setEligibilityValidation ====================

    function test_EnableEligibilityValidation() public {
        vm.prank(operator);
        assertTrue(oracle.setEligibilityValidation(true));
        assertTrue(oracle.getEligibilityValidation());
    }

    function test_DisableEligibilityValidation() public {
        // Enable first
        vm.prank(operator);
        oracle.setEligibilityValidation(true);

        // Disable
        vm.prank(operator);
        assertTrue(oracle.setEligibilityValidation(false));
        assertFalse(oracle.getEligibilityValidation());
    }

    function test_SetEligibilityValidation_EmitsEvent_OnChange() public {
        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.EligibilityValidationUpdated(true);
        vm.prank(operator);
        oracle.setEligibilityValidation(true);

        vm.expectEmit(address(oracle));
        emit IRewardsEligibilityEvents.EligibilityValidationUpdated(false);
        vm.prank(operator);
        oracle.setEligibilityValidation(false);
    }

    function test_SetEligibilityValidation_Idempotent_NoEvent() public {
        // Already disabled by default — setting false again should emit nothing
        vm.recordLogs();
        vm.prank(operator);
        oracle.setEligibilityValidation(false);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        // Enable, then set true again
        vm.prank(operator);
        oracle.setEligibilityValidation(true);

        vm.recordLogs();
        vm.prank(operator);
        oracle.setEligibilityValidation(true);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
