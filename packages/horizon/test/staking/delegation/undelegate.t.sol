// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";

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

        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        assertEq(thawRequest.shares, delegation.shares);
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
        overDelegationShares = bound(overDelegationShares, delegation.shares + 1, MAX_STAKING_TOKENS);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientShares(uint256,uint256)",
            delegation.shares,
            overDelegationShares
        );
        vm.expectRevert(expectedError);
        _undelegate(overDelegationShares, subgraphDataServiceAddress);
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
        _undelegate(withdrawShares, subgraphDataServiceAddress);
    }

    function testUndelegate_LegacySubgraphService(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer {
        amount = bound(amount, MIN_PROVISION_SIZE, MAX_STAKING_TOKENS);
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(subgraphDataServiceLegacyAddress, amount, 0, 0);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceLegacyAddress);
        Delegation memory delegation = _getDelegation(subgraphDataServiceLegacyAddress);
        _undelegate(delegation.shares, subgraphDataServiceLegacyAddress);

        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceLegacyAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        assertEq(thawRequest.shares, delegation.shares);
    }
}