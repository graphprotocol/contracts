// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { ILinkedList } from "@graphprotocol/interfaces/contracts/horizon/internal/ILinkedList.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingWithdrawDelegationTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testWithdrawDelegation_Tokens(
        uint256 delegationAmount,
        uint256 withdrawShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(withdrawShares)
    {
        ILinkedList.List memory thawingRequests = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        ThawRequest memory thawRequest = staking.getThawRequest(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            thawingRequests.tail
        );

        skip(thawRequest.thawingUntil + 1);

        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testWithdrawDelegation_RevertWhen_NotThawing(
        uint256 delegationAmount
    ) public useIndexer useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD) useDelegation(delegationAmount) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testWithdrawDelegation_ZeroTokens(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(delegationAmount)
    {
        uint256 previousBalance = token.balanceOf(users.delegator);
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);

        // Nothing changed since thawing period hasn't finished
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);
    }

    function testWithdrawDelegation_LegacySubgraphService(uint256 delegationAmount) public useIndexer {
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 10_000_000 ether, 0, MAX_THAWING_PERIOD);

        resetPrank(users.delegator);
        _delegate(users.indexer, delegationAmount);
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            true
        );
        _undelegate(users.indexer, delegation.shares);

        ILinkedList.List memory thawingRequests = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceLegacyAddress,
            users.delegator
        );
        ThawRequest memory thawRequest = staking.getThawRequest(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            thawingRequests.tail
        );

        skip(thawRequest.thawingUntil + 1);

        _withdrawDelegated(users.indexer, subgraphDataServiceLegacyAddress, 0);
    }

    function testWithdrawDelegation_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, MAX_THAWING_PERIOD) useDelegationSlashing {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION * 2, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // undelegate some shares
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares / 2);

        // slash all of the provision + delegation
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);

        // fast forward in time and attempt to withdraw
        skip(MAX_THAWING_PERIOD + 1);
        resetPrank(users.delegator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testWithdrawDelegation_AfterRecoveringPool(
        uint256 tokens
    ) public useIndexer useProvision(tokens, 0, MAX_THAWING_PERIOD) useDelegationSlashing {
        uint256 delegationTokens = MAX_STAKING_TOKENS / 10;

        // delegate
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // undelegate some shares
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares / 2);

        // slash all of the provision + delegation
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);

        // recover the delegation pool
        resetPrank(users.indexer);
        token.approve(address(staking), delegationTokens);
        _addToDelegationPool(users.indexer, subgraphDataServiceAddress, delegationTokens);

        // fast forward in time and withdraw - this withdraw will net 0 tokens
        skip(MAX_THAWING_PERIOD + 1);
        resetPrank(users.delegator);
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testWithdrawDelegation_GetThawedTokens(
        uint256 delegationAmount,
        uint256 withdrawShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(withdrawShares)
    {
        ILinkedList.List memory thawingRequests = staking.getThawRequestList(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        ThawRequest memory thawRequest = staking.getThawRequest(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            thawingRequests.tail
        );

        // Before thawing period passes, thawed tokens should be 0
        uint256 thawedTokensBefore = staking.getThawedTokens(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );
        assertEq(thawedTokensBefore, 0);

        // Skip past thawing period
        skip(thawRequest.thawingUntil + 1);

        // After thawing period, thawed tokens should match expected amount
        uint256 thawedTokensAfter = staking.getThawedTokens(
            IHorizonStakingTypes.ThawRequestType.Delegation,
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator
        );

        // Thawed tokens should be greater than 0 and should match what we can withdraw
        assertGt(thawedTokensAfter, 0);

        // Withdraw and verify the amount matches
        uint256 balanceBefore = token.balanceOf(users.delegator);
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, 0);
        uint256 balanceAfter = token.balanceOf(users.delegator);

        assertEq(balanceAfter - balanceBefore, thawedTokensAfter);
    }
}
