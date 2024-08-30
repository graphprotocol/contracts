// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingUndelegateTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testUndelegate_Tokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);
    }

    function testMultipleUndelegate_Tokens(
        uint256 amount,
        uint256 delegationAmount,
        uint256 undelegateSteps
    ) public useIndexer useProvision(amount, 0, 0) {
        undelegateSteps = bound(undelegateSteps, 1, 10);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION + 10 wei, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationAmount, 0);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);

        // there is a min delegation amount of 1 ether after undelegating
        uint256 undelegateAmount = (delegation.shares - 1 ether) / undelegateSteps;
        for (uint i = 0; i < undelegateSteps; i++) {
            _undelegate(users.indexer, subgraphDataServiceAddress, undelegateAmount);
        }
    }

    function testUndelegate_RevertWhen_TooManyUndelegations()
        public
        useIndexer
        useProvision(1000 ether, 0, 0)
        useDelegation(1000 ether)
    {
        resetPrank(users.delegator);

        for (uint i = 0; i < MAX_THAW_REQUESTS; i++) {
            _undelegate(users.indexer, subgraphDataServiceAddress, 1 ether);
        }

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingTooManyThawRequests()");
        vm.expectRevert(expectedError);
        staking.undelegate(users.indexer, subgraphDataServiceAddress, 1 ether);
    }

    function testUndelegate_RevertWhen_ZeroShares(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroShares()");
        vm.expectRevert(expectedError);
        staking.undelegate(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testUndelegate_RevertWhen_OverShares(
        uint256 amount,
        uint256 delegationAmount,
        uint256 overDelegationShares
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        overDelegationShares = bound(overDelegationShares, delegation.shares + 1, MAX_STAKING_TOKENS + 1);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientShares(uint256,uint256)",
            delegation.shares,
            overDelegationShares
        );
        vm.expectRevert(expectedError);
        staking.undelegate(users.indexer, subgraphDataServiceAddress, overDelegationShares);
    }

    function testUndelegate_RevertWhen_UndelegateLeavesInsufficientTokens(
        uint256 delegationAmount,
        uint256 withdrawShares
    ) public useIndexer useProvision(10_000_000 ether, 0, 0) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        uint256 minShares = delegationAmount - MIN_DELEGATION + 1;
        withdrawShares = bound(withdrawShares, minShares, delegationAmount - 1);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            delegationAmount - withdrawShares,
            MIN_DELEGATION
        );
        vm.expectRevert(expectedError);
        staking.undelegate(users.indexer, subgraphDataServiceAddress, withdrawShares);
    }

    function testUndelegate_LegacySubgraphService(uint256 amount, uint256 delegationAmount) public useIndexer {
        amount = bound(amount, 1, MAX_STAKING_TOKENS);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegate(users.indexer, delegationAmount);

        Delegation memory delegation = _getDelegation(subgraphDataServiceLegacyAddress);
        _undelegate(users.indexer, delegation.shares);
    }

    function testUndelegate_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing() {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
        
        resetPrank(users.delegator);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);
    }
}
