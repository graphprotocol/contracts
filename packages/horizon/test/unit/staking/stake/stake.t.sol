// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingStakeTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testStake_Tokens(uint256 amount) public useIndexer {
        amount = bound(amount, 1, MAX_STAKING_TOKENS);
        _stake(amount);
    }

    function testStake_RevertWhen_ZeroTokens() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.stake(0);
    }

    function testStakeTo_Tokens(uint256 amount) public useOperator {
        amount = bound(amount, 1, MAX_STAKING_TOKENS);
        _stakeTo(users.indexer, amount);
    }

    function testStakeTo_RevertWhen_ZeroTokens() public useOperator {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.stakeTo(users.indexer, 0);
    }
}
