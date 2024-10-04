// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDelegationAddToPoolTest is HorizonStakingTest {

    modifier useValidDelegationAmount(uint256 tokens) {
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _;
    }

    modifier useValidAddToPoolAmount(uint256 tokens) {
        vm.assume(tokens > 0);
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _;
    }

    /*
     * TESTS
     */

    function test_Delegation_AddToPool_Verifier(
        uint256 amount,
        uint256 delegationAmount,
        uint256 addToPoolAmount
    ) public useIndexer useProvision(amount, 0, 0) useValidDelegationAmount(delegationAmount) useValidAddToPoolAmount(addToPoolAmount) {
        delegationAmount = bound(delegationAmount, 1, MAX_STAKING_TOKENS);

        // Initialize delegation pool
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);

        resetPrank(subgraphDataServiceAddress);
        mint(subgraphDataServiceAddress, addToPoolAmount);
        token.approve(address(staking), addToPoolAmount);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, addToPoolAmount);
    }

    function test_Delegation_AddToPool_Payments(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useValidDelegationAmount(delegationAmount) useValidAddToPoolAmount(delegationAmount) {
        // Initialize delegation pool
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
        
        resetPrank(address(payments));
        mint(address(payments), delegationAmount);
        token.approve(address(staking), delegationAmount);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, delegationAmount);
    }

    function test_Delegation_AddToPool_RevertWhen_ZeroTokens(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(subgraphDataServiceAddress);
        bytes memory expectedError = abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidZeroTokens.selector);
        vm.expectRevert(expectedError);
        staking.addToDelegationPool(users.indexer, subgraphDataServiceAddress, 0);
    }

    function test_Delegation_AddToPool_RevertWhen_PoolHasNoShares(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) {
        vm.startPrank(subgraphDataServiceAddress);
        bytes memory expectedError = abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.addToDelegationPool(users.indexer, subgraphDataServiceAddress, 1);
    }

    function test_Delegation_AddToPool_RevertWhen_NoProvision() public {
        vm.startPrank(subgraphDataServiceAddress);
        bytes memory expectedError = abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidProvision.selector,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.addToDelegationPool(users.indexer, subgraphDataServiceAddress, 1);
    }

    function test_Delegation_AddToPool_WhenInvalidPool(
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
    }


    function test_Delegation_AddToPool_WhenInvalidPool_RevertWhen_PoolHasNoShares(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 recoverAmount
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing() {
        recoverAmount = bound(recoverAmount, 1, MAX_STAKING_TOKENS);
        delegationTokens = bound(delegationTokens, 1, MAX_STAKING_TOKENS);

        // create delegation pool
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // undelegate shares so we have thawing shares/tokens
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        resetPrank(users.delegator);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);

        // slash entire provision + pool
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);

        // addTokens
        bytes memory expectedError = abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.addToDelegationPool(users.indexer, subgraphDataServiceAddress, 1);
    }
}