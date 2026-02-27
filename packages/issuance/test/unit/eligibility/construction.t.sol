// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseUpgradeable } from "../../../contracts/common/BaseUpgradeable.sol";
import { RewardsEligibilityOracle } from "../../../contracts/eligibility/RewardsEligibilityOracle.sol";
import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Construction and initialization tests for RewardsEligibilityOracle.
contract RewardsEligibilityOracleConstructionTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Constructor ====================

    function test_Revert_ZeroGraphTokenAddress() public {
        vm.expectRevert(BaseUpgradeable.GraphTokenCannotBeZeroAddress.selector);
        new RewardsEligibilityOracle(address(0));
    }

    function test_Revert_ZeroGovernorAddress() public {
        RewardsEligibilityOracle impl = new RewardsEligibilityOracle(address(token));
        bytes memory initData = abi.encodeCall(RewardsEligibilityOracle.initialize, (address(0)));

        vm.expectRevert(BaseUpgradeable.GovernorCannotBeZeroAddress.selector);
        new TransparentUpgradeableProxy(address(impl), address(this), initData);
    }

    // ==================== Initialization ====================

    function test_Init_GovernorRoleSet() public view {
        assertTrue(oracle.hasRole(GOVERNOR_ROLE, governor));
    }

    function test_Init_OracleRoleNotSetInitially() public view {
        assertFalse(oracle.hasRole(ORACLE_ROLE, operator));
        assertFalse(oracle.hasRole(ORACLE_ROLE, governor));
    }

    function test_Init_DefaultEligibilityPeriod() public view {
        assertEq(oracle.getEligibilityPeriod(), DEFAULT_ELIGIBILITY_PERIOD);
    }

    function test_Init_EligibilityValidationDisabled() public view {
        assertFalse(oracle.getEligibilityValidation());
    }

    function test_Init_DefaultOracleUpdateTimeout() public view {
        assertEq(oracle.getOracleUpdateTimeout(), DEFAULT_ORACLE_TIMEOUT);
    }

    function test_Init_LastOracleUpdateTimeIsZero() public view {
        assertEq(oracle.getLastOracleUpdateTime(), 0);
    }

    function test_Revert_DoubleInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oracle.initialize(governor);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
