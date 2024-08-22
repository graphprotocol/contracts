// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDelegateTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testDelegate_Tokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
    }

    function testDelegate_Tokens_WhenThawing(
        uint256 amount,
        uint256 delegationAmount,
        uint256 undelegateAmount
    ) public useIndexer useProvision(amount, 0, 1 days) {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);
        // there is a min delegation amount of 1 ether after undelegating so we start with 1 ether + 1 wei
        delegationAmount = bound(delegationAmount, 1 ether + 1 wei, MAX_STAKING_TOKENS);

        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);

        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        undelegateAmount = bound(undelegateAmount, 1 wei, delegation.shares - 1 ether);
        _undelegate(users.indexer, subgraphDataServiceAddress, undelegateAmount);

        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
    }

    function testDelegate_RevertWhen_ZeroTokens(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
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

    function testDelegate_LegacySubgraphService(uint256 amount, uint256 delegationAmount) public useIndexer {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegateLegacy(users.indexer, delegationAmount);
    }

    function testDelegate_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing(true) {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
        
        resetPrank(users.delegator);
        token.approve(address(staking), delegationTokens);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
    }

    function testDelegate_RevertWhen_ThawingShares_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing(true) {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);

        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
        
        resetPrank(users.delegator);
        token.approve(address(staking), delegationTokens);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
    }
}
