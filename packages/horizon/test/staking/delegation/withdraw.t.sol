// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

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
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0x0), 0);
    }

    function _expectedTokensFromThawRequest(ThawRequest memory thawRequest) private view returns (uint256) {
        DelegationPool memory pool = _getDelegationPool();
        return (thawRequest.shares * pool.tokensThawing) / pool.sharesThawing;
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
        Delegation memory thawingDelegation = _getDelegation();
        ThawRequest memory thawRequest = staking.getThawRequest(thawingDelegation.lastThawRequestId);

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
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNotEnoughThawedTokens()");
        vm.expectRevert(expectedError);
        _withdrawDelegated();
    }
}