// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { LinkedList } from "../../../contracts/libraries/LinkedList.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingWithdrawDelegationTest is HorizonStakingTest {

    /*
     * MODIFIERS
     */

    modifier useUndelegate(uint256 shares) {
        vm.stopPrank();
        vm.startPrank(users.delegator);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        shares = bound(shares, 1, delegation.shares);
        
        if (shares != delegation.shares) {
            DelegationPool memory pool = _getDelegationPool(subgraphDataServiceAddress);
            uint256 tokens = (shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
            uint256 newTokensThawing = pool.tokensThawing + tokens;
            uint256 remainingTokens = (delegation.shares * (pool.tokens - newTokensThawing)) / pool.shares;
            vm.assume(remainingTokens >= MIN_DELEGATION);
        }
        
        _undelegate(shares, subgraphDataServiceAddress);
        _;
    }

    /*
     * HELPERS
     */

    function _withdrawDelegated(address _verifier, address _newIndexer) private {
        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, _verifier, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        uint256 previousBalance = token.balanceOf(users.delegator);
        uint256 expectedTokens = _expectedTokensFromThawRequest(thawRequest, _verifier);
        staking.withdrawDelegated(users.indexer, _verifier, _newIndexer, 0, 0);

        if (_newIndexer != address(0)) {
            uint256 delegatedTokens = staking.getDelegatedTokensAvailable(_newIndexer, _verifier);
            assertEq(delegatedTokens, expectedTokens);
        } else {
            uint256 newBalance = token.balanceOf(users.delegator);
            assertEq(newBalance - previousBalance, expectedTokens);
        }
    }

    function _expectedTokensFromThawRequest(ThawRequest memory thawRequest, address verifier) private view returns (uint256) {
        DelegationPool memory pool = _getDelegationPool(verifier);
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
        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        skip(thawRequest.thawingUntil + 1);

        _withdrawDelegated(subgraphDataServiceAddress, address(0));
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
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
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
        _withdrawDelegated(subgraphDataServiceAddress, newIndexer);
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
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
        
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

    function testWithdrawDelegation_LegacySubgraphService(uint256 delegationAmount) public useIndexer {
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        _createProvision(subgraphDataServiceLegacyAddress, 10_000_000 ether, 0, MAX_THAWING_PERIOD);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceLegacyAddress);
        Delegation memory delegation = _getDelegation(subgraphDataServiceLegacyAddress);
        _undelegate(delegation.shares, subgraphDataServiceLegacyAddress);

        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceLegacyAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        skip(thawRequest.thawingUntil + 1);

        _withdrawDelegated(subgraphDataServiceLegacyAddress, address(0));
    }

    function testWithdrawDelegation_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, MAX_THAWING_PERIOD) useDelegationSlashing(true) {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(delegationTokens, subgraphDataServiceAddress);
        Delegation memory delegation = _getDelegation(subgraphDataServiceAddress);
        _undelegate(delegation.shares, subgraphDataServiceAddress);

        skip(MAX_THAWING_PERIOD + 1);

        resetPrank(subgraphDataServiceAddress);
        _slash(tokens + delegationTokens, 0);
        
        resetPrank(users.delegator);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
    }
}