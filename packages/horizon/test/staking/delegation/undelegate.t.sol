// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingUndelegateTest is HorizonStakingTest {

    function testUndelegate_Tokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        // TODO: maybe create a changePrank
        vm.stopPrank();
        vm.startPrank(users.delegator);
        Delegation memory delegation = _getDelegation();
        _undelegate(delegation.shares);

        Delegation memory thawingDelegation = _getDelegation();
        ThawRequest memory thawRequest = staking.getThawRequest(thawingDelegation.lastThawRequestId);

        assertEq(thawRequest.shares, delegation.shares);
    }

    function testUndelegate_RevertWhen_ZeroTokens(
        uint256 amount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        // TODO: maybe create a changePrank
        vm.stopPrank();
        vm.startPrank(users.delegator);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        _undelegate(0);
    }

    function testUndelegate_RevertWhen_OverUndelegation(
        uint256 amount,
        uint256 delegationAmount,
        uint256 overDelegationShares
    ) public useIndexer useProvision(amount, 0, 0) useDelegation(delegationAmount) {
        // TODO: maybe create a changePrank
        vm.stopPrank();
        vm.startPrank(users.delegator);
        Delegation memory delegation = _getDelegation();
        vm.assume(overDelegationShares > delegation.shares);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            overDelegationShares,
            delegation.shares
        );
        vm.expectRevert(expectedError);
        _undelegate(overDelegationShares);
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
        // TODO: maybe create a changePrank
        vm.stopPrank();
        vm.startPrank(users.delegator);
        uint256 minShares = delegationAmount - MIN_DELEGATION + 1;
        withdrawShares = bound(withdrawShares, minShares, delegationAmount - 1);
        
        vm.expectRevert("!minimum-delegation");
        _undelegate(withdrawShares);
    }
}