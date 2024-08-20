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
        _undelegate(delegation.shares, subgraphDataServiceAddress);
    }

    function testUndelegate_RevertWhen_ZeroTokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        resetPrank(users.delegator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroShares()");
        vm.expectRevert(expectedError);
        _undelegate(0, subgraphDataServiceAddress);
    }

    function testUndelegate_RevertWhen_OverUndelegation(
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
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, 0)
        useDelegation(delegationAmount)
    {
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

    function testUndelegate_LegacySubgraphService(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer {
        amount = bound(amount, 1, MAX_STAKING_TOKENS);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceLegacyAddress);
        Delegation memory delegation = _getDelegation(subgraphDataServiceLegacyAddress);
        _undelegate(delegation.shares, subgraphDataServiceLegacyAddress);
    }

    function testUndelegate_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationSlashing(true) {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(delegationTokens, subgraphDataServiceAddress);

        resetPrank(subgraphDataServiceAddress);
        _slash(tokens + delegationTokens, 0);
        
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