// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingTest is HorizonStakingSharedTest {

    modifier useOperator() {
        vm.startPrank(users.operator);
        _;
        vm.stopPrank();
    }

    modifier useStake(uint256 amount) {
        vm.assume(amount > 0);
        approve(address(staking), amount);
        staking.stake(amount);
        _;
    }

    modifier useStakeTo(address to, uint256 amount) {
        vm.assume(amount > 0);
        _stakeTo(to, amount);
        _;
    }

    function _stakeTo(address to, uint256 amount) internal {
        approve(address(staking), amount);
        staking.stakeTo(to, amount);
    }
}