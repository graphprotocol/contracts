// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { RewardsEligibilityOracleSharedTest } from "./shared.t.sol";

/// @notice Access control tests for RewardsEligibilityOracle.
contract RewardsEligibilityOracleAccessControlTest is RewardsEligibilityOracleSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Role Management ====================

    function test_OperatorCanGrantOracleRole() public {
        _setupOperatorRole();

        vm.prank(operator);
        oracle.grantRole(ORACLE_ROLE, oracleAccount);
        assertTrue(oracle.hasRole(ORACLE_ROLE, oracleAccount));
    }

    function test_OperatorCanRevokeOracleRole() public {
        _setupOperatorRole();
        vm.prank(operator);
        oracle.grantRole(ORACLE_ROLE, oracleAccount);

        vm.prank(operator);
        oracle.revokeRole(ORACLE_ROLE, oracleAccount);
        assertFalse(oracle.hasRole(ORACLE_ROLE, oracleAccount));
    }

    function test_Revert_UnauthorizedCannotGrantOracleRole() public {
        _setupOperatorRole();

        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.grantRole(ORACLE_ROLE, oracleAccount);
    }

    function test_Revert_UnauthorizedCannotRevokeOracleRole() public {
        _setupOracleRole();

        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.revokeRole(ORACLE_ROLE, oracleAccount);
    }

    // ==================== ORACLE_ROLE ====================

    function test_Revert_NonOracleCannotRenew() public {
        address[] memory indexers = new address[](1);
        indexers[0] = indexer1;

        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.renewIndexerEligibility(indexers, "");
    }

    // ==================== PAUSE_ROLE ====================

    function test_PauseRoleCanPauseAndUnpause() public {
        vm.prank(governor);
        oracle.grantRole(PAUSE_ROLE, operator);

        vm.prank(operator);
        oracle.pause();
        assertTrue(oracle.paused());

        vm.prank(operator);
        oracle.unpause();
        assertFalse(oracle.paused());
    }

    function test_Revert_NonPauseRoleCannotPause() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.pause();
    }

    function test_Revert_NonPauseRoleCannotUnpause() public {
        vm.prank(governor);
        oracle.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        oracle.pause();

        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.unpause();
    }

    // ==================== OPERATOR_ROLE ====================

    function test_Revert_NonOperatorCannotSetEligibilityPeriod() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.setEligibilityPeriod(30 days);
    }

    function test_Revert_NonOperatorCannotSetOracleUpdateTimeout() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.setOracleUpdateTimeout(60 days);
    }

    function test_Revert_NonOperatorCannotSetEligibilityValidation() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        oracle.setEligibilityValidation(true);
    }

    // ==================== Role Hierarchy ====================

    function test_GovernorRoleAdminOfItself() public view {
        assertEq(oracle.getRoleAdmin(GOVERNOR_ROLE), GOVERNOR_ROLE);
    }

    function test_GovernorIsAdminOfPauseRole() public view {
        assertEq(oracle.getRoleAdmin(PAUSE_ROLE), GOVERNOR_ROLE);
    }

    function test_GovernorIsAdminOfOperatorRole() public view {
        assertEq(oracle.getRoleAdmin(OPERATOR_ROLE), GOVERNOR_ROLE);
    }

    function test_OperatorIsAdminOfOracleRole() public view {
        assertEq(oracle.getRoleAdmin(ORACLE_ROLE), OPERATOR_ROLE);
    }

    // ==================== Role Enumeration ====================

    function test_RoleMemberCount() public {
        assertEq(oracle.getRoleMemberCount(GOVERNOR_ROLE), 1);

        uint256 before = oracle.getRoleMemberCount(OPERATOR_ROLE);

        vm.prank(governor);
        oracle.grantRole(OPERATOR_ROLE, operator);
        assertEq(oracle.getRoleMemberCount(OPERATOR_ROLE), before + 1);

        vm.prank(governor);
        oracle.revokeRole(OPERATOR_ROLE, operator);
        assertEq(oracle.getRoleMemberCount(OPERATOR_ROLE), before);
    }

    function test_EnumerateRoleMembers() public {
        assertEq(oracle.getRoleMember(GOVERNOR_ROLE, 0), governor);

        vm.prank(governor);
        oracle.grantRole(OPERATOR_ROLE, indexer1);
        vm.prank(governor);
        oracle.grantRole(OPERATOR_ROLE, indexer2);

        uint256 count = oracle.getRoleMemberCount(OPERATOR_ROLE);
        assertGe(count, 2);

        // Collect members
        bool foundIndexer1 = false;
        bool foundIndexer2 = false;
        for (uint256 i = 0; i < count; ++i) {
            address member = oracle.getRoleMember(OPERATOR_ROLE, i);
            if (member == indexer1) foundIndexer1 = true;
            if (member == indexer2) foundIndexer2 = true;
        }
        assertTrue(foundIndexer1);
        assertTrue(foundIndexer2);
    }

    function test_Revert_OutOfBoundsIndex() public {
        uint256 count = oracle.getRoleMemberCount(GOVERNOR_ROLE);

        vm.expectRevert();
        oracle.getRoleMember(GOVERNOR_ROLE, count);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
