// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "./HorizonStaking.t.sol";

contract HorizonStakingStakeTest is HorizonStakingTest {

    function testStake_Tokens(uint256 amount) public useIndexer useStake(amount) {
        assertTrue(staking.getStake(address(users.indexer)) == amount);
    }

    function testStake_RevertWhen_ZeroTokens() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.stake(0);
    }

    function testStakeTo_Tokens(uint256 amount) public useOperator useStakeTo(users.indexer, amount) {
        assertTrue(staking.getStake(address(users.indexer)) == amount);
    }

    function testStakeTo_RevertWhen_ZeroTokens() public useOperator {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.stakeTo(users.indexer, 0);
    }
}