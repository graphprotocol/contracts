// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";

contract HorizonStakingWithdrawDelegationTest is HorizonStakingTest {

    modifier useUndelegate(uint256 shares) {
        vm.stopPrank();
        vm.startPrank(users.delegator);
        Delegation memory delegation = _getDelegation();
        shares = bound(shares, 1, delegation.shares);
        
        if (shares != delegation.shares) {
            DelegationPool memory pool = _getDelegationPool();
            uint256 tokens = (shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
            uint256 newTokensThawing = pool.tokensThawing + tokens;
            uint256 remainingTokens = (delegation.shares * (pool.tokens - newTokensThawing)) / pool.shares;
            vm.assume(remainingTokens >= MIN_DELEGATION);
        }
        
        _undelegate(shares);
        _;
    }

    function _withdrawDelegated() private {
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0x0), 0, 0);
    }

    function _expectedTokensFromThawRequest(ThawRequest memory thawRequest) private view returns (uint256) {
        DelegationPool memory pool = _getDelegationPool();
        return (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing;
    }

    function _setupNewIndexer(uint256 tokens) private returns(address) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        address newIndexer = createUser("newIndexer");
        vm.startPrank(newIndexer);
        token.approve(address(staking), tokens);
        staking.stakeTo(newIndexer, tokens);
        staking.provision(newIndexer,subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);
        vm.startPrank(msgSender);
        return newIndexer;
    }

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
        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        skip(thawRequest.thawingUntil + 1);

        uint256 previousBalance = token.balanceOf(users.delegator);
        uint256 expectedTokens = _expectedTokensFromThawRequest(thawRequest);
        _withdrawDelegated();
        
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance - previousBalance, expectedTokens);
    }

    function testWithdrawDelegation_RevertWhen_NotThawing(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
    {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        _withdrawDelegated();
    }

    function testWithdrawDelegation_MoveToNewServiceProvider(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(delegationAmount)
    {
        skip(MAX_THAWING_PERIOD + 1);

        // Setup new service provider
        address newIndexer = _setupNewIndexer(10_000_000 ether);

        uint256 previousBalance = token.balanceOf(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, newIndexer, 0, 0);
        
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(newIndexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, delegationAmount);
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
        _withdrawDelegated();
        
        // Nothing changed since thawing period haven't finished
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);
    }

    function testWithdrawDelegation_MoveZeroTokensToNewServiceProvider(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(delegationAmount)
    {
        // Setup new service provider
        address newIndexer = _setupNewIndexer(10_000_000 ether);

        uint256 previousBalance = token.balanceOf(users.delegator);
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, newIndexer, 0, 0);
        
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(newIndexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, 0);
    }
}