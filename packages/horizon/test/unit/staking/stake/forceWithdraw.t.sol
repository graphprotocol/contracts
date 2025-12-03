// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingForceWithdrawTest is HorizonStakingTest {
    /*
     * HELPERS
     */

    function _forceWithdraw(address _serviceProvider) internal {
        (, address msgSender, ) = vm.readCallers();

        // before
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(_serviceProvider);
        uint256 beforeServiceProviderBalance = token.balanceOf(_serviceProvider);
        uint256 beforeCallerBalance = token.balanceOf(msgSender);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        // forceWithdraw
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.HorizonStakeWithdrawn(
            _serviceProvider,
            beforeServiceProvider.__DEPRECATED_tokensLocked
        );
        staking.forceWithdraw(_serviceProvider);

        // after
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(_serviceProvider);
        uint256 afterServiceProviderBalance = token.balanceOf(_serviceProvider);
        uint256 afterCallerBalance = token.balanceOf(msgSender);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        // assert - tokens go to service provider, not caller
        assertEq(
            afterServiceProviderBalance - beforeServiceProviderBalance,
            beforeServiceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(afterCallerBalance, beforeCallerBalance); // caller balance unchanged
        assertEq(beforeStakingBalance - afterStakingBalance, beforeServiceProvider.__DEPRECATED_tokensLocked);

        // assert - service provider state updated
        assertEq(
            afterServiceProvider.tokensStaked,
            beforeServiceProvider.tokensStaked - beforeServiceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(afterServiceProvider.tokensProvisioned, beforeServiceProvider.tokensProvisioned);
        assertEq(afterServiceProvider.__DEPRECATED_tokensAllocated, beforeServiceProvider.__DEPRECATED_tokensAllocated);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, 0);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLockedUntil, 0);
    }

    /*
     * TESTS
     */

    function testForceWithdraw_Tokens(uint256 tokens, uint256 tokensLocked) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensLocked = bound(tokensLocked, 1, tokens);

        // simulate locked tokens ready to withdraw
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, tokensLocked, block.number, 0);

        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);

        // switch to a different user (not the service provider)
        resetPrank(users.delegator);

        _forceWithdraw(users.indexer);
    }

    function testForceWithdraw_CalledByServiceProvider(uint256 tokens, uint256 tokensLocked) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensLocked = bound(tokensLocked, 1, tokens);

        // simulate locked tokens ready to withdraw
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, tokensLocked, block.number, 0);

        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);

        // before
        ServiceProviderInternal memory beforeServiceProvider = _getStorage_ServiceProviderInternal(users.indexer);
        uint256 beforeServiceProviderBalance = token.balanceOf(users.indexer);
        uint256 beforeStakingBalance = token.balanceOf(address(staking));

        // service provider can also call forceWithdraw on themselves
        vm.expectEmit(address(staking));
        emit IHorizonStakingMain.HorizonStakeWithdrawn(users.indexer, beforeServiceProvider.__DEPRECATED_tokensLocked);
        staking.forceWithdraw(users.indexer);

        // after
        ServiceProviderInternal memory afterServiceProvider = _getStorage_ServiceProviderInternal(users.indexer);
        uint256 afterServiceProviderBalance = token.balanceOf(users.indexer);
        uint256 afterStakingBalance = token.balanceOf(address(staking));

        // assert
        assertEq(
            afterServiceProviderBalance - beforeServiceProviderBalance,
            beforeServiceProvider.__DEPRECATED_tokensLocked
        );
        assertEq(beforeStakingBalance - afterStakingBalance, beforeServiceProvider.__DEPRECATED_tokensLocked);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLocked, 0);
        assertEq(afterServiceProvider.__DEPRECATED_tokensLockedUntil, 0);
    }

    function testForceWithdraw_RevertWhen_ZeroTokens(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        // simulate zero locked tokens
        token.transfer(address(staking), tokens);
        _setStorage_ServiceProvider(users.indexer, tokens, 0, 0, 0, 0);

        _createProvision(users.indexer, subgraphDataServiceLegacyAddress, tokens, 0, MAX_THAWING_PERIOD);

        // switch to a different user
        resetPrank(users.delegator);

        vm.expectRevert(abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingInvalidZeroTokens.selector));
        staking.forceWithdraw(users.indexer);
    }
}
