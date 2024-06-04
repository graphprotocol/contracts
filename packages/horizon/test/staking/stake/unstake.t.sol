// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingUnstakeTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testUnstake_Tokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
        useThawAndDeprovision(amount, thawingPeriod)
    {
        uint256 previousIndexerTokens = token.balanceOf(users.indexer);
        staking.unstake(amount);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0 ether);

        uint256 newIndexerBalance = token.balanceOf(users.indexer);
        assertEq(newIndexerBalance - previousIndexerTokens, amount);
    }

    function testUnstake_RevertWhen_ZeroTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
        useThawAndDeprovision(amount, thawingPeriod)
    {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.unstake(0);
    }

    function testUnstake_RevertWhen_NoIdleStake(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
    {
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            amount,
            0
        );
        vm.expectRevert(expectedError);
        staking.unstake(amount);
    }

    function testUnstake_RevertWhen_NotDeprovision(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
        useThawRequest(amount)
    {
        skip(thawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            amount,
            0
        );
        vm.expectRevert(expectedError);
        staking.unstake(amount);
    }
}