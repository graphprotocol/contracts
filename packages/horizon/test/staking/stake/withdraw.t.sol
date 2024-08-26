// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingWithdrawTest is HorizonStakingTest {

    /*
     * HELPERS
     */

    function _withdrawLockedTokens(uint256 tokens) private {
        uint256 previousIndexerTokens = token.balanceOf(users.indexer);
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.StakeWithdrawn(users.indexer, tokens);
        staking.withdraw();
        uint256 newIndexerBalance = token.balanceOf(users.indexer);
        assertEq(newIndexerBalance - previousIndexerTokens, tokens);
    }

    /*
     * TESTS
     */

    function testWithdraw_Tokens(uint256 tokens, uint256 tokensLocked) public useIndexer {
        vm.assume(tokens > 0);
        tokensLocked = bound(tokensLocked, 1, tokens);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);
        _storeServiceProvider(users.indexer, tokens, 0, tokensLocked, block.timestamp, 0);
        _withdrawLockedTokens(tokensLocked);
    }

    function testWithdraw_RevertWhen_ZeroTokens(uint256 tokens) public useIndexer {
        vm.assume(tokens > 0);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);
        _storeServiceProvider(users.indexer, tokens, 0, 0, block.timestamp, 0);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidZeroTokens.selector
        ));
        staking.withdraw();
    }

    function testWithdraw_RevertWhen_StillThawing(uint256 tokens, uint256 tokensLocked) public useIndexer {
        vm.assume(tokens > 0);
        tokensLocked = bound(tokensLocked, 1, tokens);
        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);
        uint256 thawUntil = block.timestamp + 1;
        _storeServiceProvider(users.indexer, tokens, 0, tokensLocked, thawUntil, 0);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingStillThawing.selector,
            thawUntil
        ));
        staking.withdraw();
    }
}