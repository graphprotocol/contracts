// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingWithdrawTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testWithdraw_Tokens(uint256 tokens, uint256 tokensLocked) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensLocked = bound(tokensLocked, 1, tokens);

        // simulate locked tokens ready to withdraw
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, tokensLocked, block.number, 0);

        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);

        _withdraw();
    }

    function testWithdraw_RevertWhen_ZeroTokens(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        // simulate zero locked tokens
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, 0, 0, 0);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidZeroTokens.selector));
        staking.withdraw();
    }

    function testWithdraw_RevertWhen_StillThawing(uint256 tokens, uint256 tokensLocked) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensLocked = bound(tokensLocked, 1, tokens);

        // simulate locked tokens still thawing
        uint256 thawUntil = block.timestamp + 1;
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, tokensLocked, thawUntil, 0);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);

        vm.expectRevert(abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingStillThawing.selector, thawUntil));
        staking.withdraw();
    }
}
