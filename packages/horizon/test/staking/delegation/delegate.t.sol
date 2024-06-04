// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDelegateTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testDelegate_Tokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, delegationAmount);
    }

    function testDelegate_RevertWhen_ZeroTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(users.delegator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.delegate(users.indexer, subgraphDataServiceAddress, 0, 0);
    }

    function testDelegate_RevertWhen_BelowMinimum(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(users.delegator);
        delegationAmount = bound(delegationAmount, 1, MIN_DELEGATION - 1);
        token.approve(address(staking), delegationAmount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            delegationAmount,
            MIN_DELEGATION
        );
        vm.expectRevert(expectedError);
        staking.delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
    }

    function testDelegate_LegacySubgraphService(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer {
        amount = bound(amount, MIN_PROVISION_SIZE, 10_000_000_000 ether);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, 10_000_000_000 ether);
        _createProvision(subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceLegacyAddress);
        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceLegacyAddress);
        assertEq(delegatedTokens, delegationAmount);
    }
}