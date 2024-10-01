// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

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
        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, false);
        shares = bound(shares, 1, delegation.shares);

        _undelegate(users.indexer, subgraphDataServiceAddress, shares);
        _;
    }

    /*
     * HELPERS
     */
    function _setupNewIndexer(uint256 tokens) private returns(address) {
        (, address msgSender,) = vm.readCallers();

        address newIndexer = createUser("newIndexer");
        vm.startPrank(newIndexer);
        _createProvision(newIndexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);

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

        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
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
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, newIndexer, 0, 0);
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
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
        
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
        _withdrawDelegated(users.indexer, subgraphDataServiceAddress, newIndexer, 0, 0);
        
        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(newIndexer, subgraphDataServiceAddress);
        assertEq(delegatedTokens, 0);
    }

    function testWithdrawDelegation_LegacySubgraphService(uint256 delegationAmount) public useIndexer {
        delegationAmount = bound(delegationAmount, 1, MAX_STAKING_TOKENS);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, 10_000_000 ether, 0, MAX_THAWING_PERIOD);

        resetPrank(users.delegator);
        _delegate(users.indexer, delegationAmount);
        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, true);
        _undelegate(users.indexer, delegation.shares);

        LinkedList.List memory thawingRequests = staking.getThawRequestList(users.indexer, subgraphDataServiceLegacyAddress, users.delegator);
        ThawRequest memory thawRequest = staking.getThawRequest(thawingRequests.tail);

        skip(thawRequest.thawingUntil + 1);

        _withdrawDelegated(users.indexer, address(0));
    }

    function testWithdrawDelegation_RevertWhen_InvalidPool(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, 0, MAX_THAWING_PERIOD) useDelegationSlashing() {
        delegationTokens = bound(delegationTokens, 1, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
        DelegationInternal memory delegation = _getStorage_Delegation(users.indexer, subgraphDataServiceAddress, users.delegator, false);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares);

        skip(MAX_THAWING_PERIOD + 1);

        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
        
        resetPrank(users.delegator);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPoolState.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        staking.withdrawDelegated(users.indexer, subgraphDataServiceAddress, address(0), 0, 0);
    }
}