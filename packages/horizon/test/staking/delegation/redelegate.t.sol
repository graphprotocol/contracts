// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingWithdrawDelegationTest is HorizonStakingTest {
    /*
     * HELPERS
     */

    function _setupNewIndexer(uint256 tokens) private returns (address) {
        (, address msgSender, ) = vm.readCallers();

        address newIndexer = createUser("newIndexer");
        vm.startPrank(newIndexer);
        _createProvision(newIndexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);

        vm.startPrank(msgSender);
        return newIndexer;
    }

    function _setupNewIndexerAndVerifier(uint256 tokens) private returns (address, address) {
        (, address msgSender, ) = vm.readCallers();

        address newIndexer = createUser("newIndexer");
        address newVerifier = makeAddr("newVerifier");
        vm.startPrank(newIndexer);
        _createProvision(newIndexer, newVerifier, tokens, 0, MAX_THAWING_PERIOD);

        vm.startPrank(msgSender);
        return (newIndexer, newVerifier);
    }

    /*
     * TESTS
     */

    function testRedelegate_MoveToNewServiceProvider(
        uint256 delegationAmount,
        uint256 withdrawShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(withdrawShares)
    {
        skip(MAX_THAWING_PERIOD + 1);

        // Setup new service provider
        address newIndexer = _setupNewIndexer(10_000_000 ether);
        _redelegate(users.indexer, subgraphDataServiceAddress, newIndexer, subgraphDataServiceAddress, 0, 0);
    }

    function testRedelegate_MoveToNewServiceProviderAndNewVerifier(
        uint256 delegationAmount,
        uint256 withdrawShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(withdrawShares)
    {
        skip(MAX_THAWING_PERIOD + 1);

        // Setup new service provider
        (address newIndexer, address newVerifier) = _setupNewIndexerAndVerifier(10_000_000 ether);
        _redelegate(users.indexer, subgraphDataServiceAddress, newIndexer, newVerifier, 0, 0);
    }

    function testRedelegate_RevertWhen_VerifierZeroAddress(
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
        vm.expectRevert(abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidVerifierZeroAddress.selector));
        staking.redelegate(users.indexer, subgraphDataServiceAddress, newIndexer, address(0), 0, 0);
    }

    function testRedelegate_RevertWhen_ServiceProviderZeroAddress(
        uint256 delegationAmount
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(delegationAmount)
    {
        skip(MAX_THAWING_PERIOD + 1);

        // Setup new verifier
        address newVerifier = makeAddr("newVerifier");
        vm.expectRevert(
            abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidServiceProviderZeroAddress.selector)
        );
        staking.redelegate(users.indexer, subgraphDataServiceAddress, address(0), newVerifier, 0, 0);
    }

    function testRedelegate_MoveZeroTokensToNewServiceProviderAndVerifier(
        uint256 delegationAmount,
        uint256 withdrawShares
    )
        public
        useIndexer
        useProvision(10_000_000 ether, 0, MAX_THAWING_PERIOD)
        useDelegation(delegationAmount)
        useUndelegate(withdrawShares)
    {
        // Setup new service provider
        (address newIndexer, address newVerifier) = _setupNewIndexerAndVerifier(10_000_000 ether);

        uint256 previousBalance = token.balanceOf(users.delegator);
        _redelegate(users.indexer, subgraphDataServiceAddress, newIndexer, newVerifier, 0, 0);

        uint256 newBalance = token.balanceOf(users.delegator);
        assertEq(newBalance, previousBalance);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(newIndexer, newVerifier);
        assertEq(delegatedTokens, 0);
    }
}
