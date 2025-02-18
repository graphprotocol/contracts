// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingGovernanceTest is HorizonStakingTest {
    /*
     * MODIFIERS
     */

    modifier useGovernor() {
        vm.startPrank(users.governor);
        _;
    }

    /*
     * TESTS
     */

    function testGovernance_SetAllowedLockedVerifier() public useGovernor {
        _setAllowedLockedVerifier(subgraphDataServiceAddress, true);
    }

    function testGovernance_RevertWhen_SetAllowedLockedVerifier_NotGovernor() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("ManagedOnlyGovernor()");
        vm.expectRevert(expectedError);
        staking.setAllowedLockedVerifier(subgraphDataServiceAddress, true);
    }

    function testGovernance_SetDelgationSlashingEnabled() public useGovernor {
        _setDelegationSlashingEnabled();
    }

    function testGovernance_SetDelgationSlashing_NotGovernor() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("ManagedOnlyGovernor()");
        vm.expectRevert(expectedError);
        staking.setDelegationSlashingEnabled();
    }

    function testGovernance_ClearThawingPeriod(uint32 thawingPeriod) public useGovernor {
        // simulate previous thawing period
        _setStorage_DeprecatedThawingPeriod(thawingPeriod);

        _clearThawingPeriod();
    }

    function testGovernance_ClearThawingPeriod_NotGovernor() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("ManagedOnlyGovernor()");
        vm.expectRevert(expectedError);
        staking.clearThawingPeriod();
    }

    function testGovernance__SetMaxThawingPeriod(uint64 maxThawingPeriod) public useGovernor {
        _setMaxThawingPeriod(maxThawingPeriod);
    }

    function testGovernance__SetMaxThawingPeriod_NotGovernor() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("ManagedOnlyGovernor()");
        vm.expectRevert(expectedError);
        staking.setMaxThawingPeriod(MAX_THAWING_PERIOD);
    }
}
