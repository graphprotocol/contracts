// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDelegationAddToPoolTest is HorizonStakingTest {

    modifier useValidDelegationAmount(uint256 tokens) {
        vm.assume(tokens > 0);
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _;
    }

    /*
     * TESTS
     */

    function test_Delegation_AddToPool_Verifier(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useValidDelegationAmount(delegationAmount) {
        uint256 stakingPreviousBalance = token.balanceOf(address(staking));
        
        resetPrank(subgraphDataServiceAddress);
        mint(subgraphDataServiceAddress, delegationAmount);
        token.approve(address(staking), delegationAmount);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, delegationAmount);
        
        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, delegationAmount);
        assertEq(token.balanceOf(subgraphDataServiceAddress), 0);
        assertEq(token.balanceOf(address(staking)), stakingPreviousBalance + delegationAmount);
    }

    function test_Delegation_AddToPool_Payments(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useValidDelegationAmount(delegationAmount) {
        uint256 stakingPreviousBalance = token.balanceOf(address(staking));
        
        resetPrank(address(payments));
        mint(address(payments), delegationAmount);
        token.approve(address(staking), delegationAmount);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, delegationAmount);
        
        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, delegationAmount);
        assertEq(token.balanceOf(subgraphDataServiceAddress), 0);
        assertEq(token.balanceOf(address(staking)), stakingPreviousBalance + delegationAmount);
    }

    function test_Delegation_AddToPool_RevertWhen_ZeroTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(subgraphDataServiceAddress);
        bytes memory expectedError = abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidZeroTokens.selector);
        vm.expectRevert(expectedError);
        staking.addToDelegationPool(users.indexer, subgraphDataServiceAddress, 0);
    }

    // TODO: test recovering an invalid delegation pool
}