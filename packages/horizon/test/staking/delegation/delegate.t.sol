// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

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

        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, false);
        undelegateAmount = bound(undelegateAmount, 1 wei, delegation.shares - 1 ether);
        _undelegate(users.indexer, subgraphDataServiceAddress, undelegateAmount);

        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
    }

    function testDelegate_Tokens_WhenAllThawing(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 1 days) {
        delegationAmount = bound(delegationAmount, 1 ether, MAX_STAKING_TOKENS);

        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);

        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, false);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);

        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0); 
    }

    function testDelegate_RevertWhen_ZeroTokens(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(users.delegator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.delegate(users.indexer, subgraphDataServiceAddress, 0, 0);
    }

    function testDelegate_LegacySubgraphService(uint256 amount, uint256 delegationAmount) public useIndexer {
        amount = bound(amount, 1 ether, MAX_STAKING_TOKENS);
        delegationAmount = bound(delegationAmount, 1, MAX_STAKING_TOKENS);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegate(users.indexer, delegationAmount);
    }

    function testDelegate_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing() {
        delegationTokens = bound(delegationTokens, 1, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // slash entire provision + pool
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
        
        // attempt to delegate to a pool on invalid state, should revert
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
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing() {
        delegationTokens = bound(delegationTokens, 2, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // undelegate some shares but not all
        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, false);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares / 2);

        // slash entire provision + pool
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);

        // attempt to delegate to a pool on invalid state, should revert
        resetPrank(users.delegator);
        token.approve(address(staking), delegationTokens);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
    }

    function testDelegate_AfterRecoveringPool(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 recoverAmount
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing() {
        recoverAmount = bound(recoverAmount, 1, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, 1, MAX_STAKING_TOKENS);

        // create delegation pool
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // slash entire provision + pool
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);

        // recover pool by adding tokens
        resetPrank(users.indexer);
        token.approve(address(staking), recoverAmount);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, recoverAmount);

        // delegate to pool - should be allowed now
        vm.assume(delegationTokens >= recoverAmount); // to avoid getting issued 0 shares
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
    }
}
