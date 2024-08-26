// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingUnstakeTest is HorizonStakingTest {

    function _storeDeprecatedThawingPeriod(uint32 _thawingPeriod) private {
        uint256 slot = 13;
        bytes32 value = bytes32(uint256(_thawingPeriod));
        vm.store(address(staking), bytes32(slot), value);
    }

    /*
     * TESTS
     */

    function testUnstake_Tokens(
        uint256 tokens,
        uint256 tokensToUnstake,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(tokens, maxVerifierCut, thawingPeriod)
    {
        tokensToUnstake = bound(tokensToUnstake, 1, tokens);

        _createThawRequest(tokens);
        skip(thawingPeriod + 1);
        _deprovision(0);
        _unstake(tokensToUnstake);
    }

    function testUnstake_LockingPeriodGreaterThanZero_TokensDoneThawing(
        uint256 tokens,
        uint256 tokensToUnstake,
        uint256 tokensLocked
    )
        public
        useIndexer
    {
        // bounds
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensToUnstake = bound(tokensToUnstake, 1, tokens);
        tokensLocked = bound(tokensLocked, 1, MAX_STAKING_TOKENS);

        // vm.store to simulate locked tokens with past locking period
        _storeDeprecatedThawingPeriod(THAWING_PERIOD_IN_BLOCKS);
        token.transfer(address(staking), tokensLocked);
        _storeServiceProvider(users.indexer, tokensLocked, 0, tokensLocked, block.number, 0);

        // create provision, thaw request and deprovision
        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);
        _createThawRequest(tokens);
        skip(MAX_THAWING_PERIOD + 1);
        _deprovision(0);

        // unstake
        _unstakeDuringLockingPeriod(tokensToUnstake, 0, tokensLocked, 0);
    }

    function testUnstake_LockingPeriodGreaterThanZero_TokensStillThawing(
        uint256 tokens,
        uint256 tokensToUnstake,
        uint256 tokensThawing,
        uint32 tokensThawingUntilBlock
    )
        public
        useIndexer
    {
        // bounds
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        tokensToUnstake = bound(tokensToUnstake, 1, tokens);
        tokensThawing = bound(tokensThawing, 1, MAX_STAKING_TOKENS);
        vm.assume(tokensThawingUntilBlock > block.number);
        vm.assume(tokensThawingUntilBlock < block.number + THAWING_PERIOD_IN_BLOCKS);

        // vm.store to simulate locked tokens still thawing
        _storeDeprecatedThawingPeriod(THAWING_PERIOD_IN_BLOCKS);
        token.transfer(address(staking), tokensThawing);
        _storeServiceProvider(users.indexer, tokensThawing, 0, tokensThawing, tokensThawingUntilBlock, 0);

        // create provision, thaw request and deprovision
        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, 0, MAX_THAWING_PERIOD);
        _createThawRequest(tokens);
        skip(MAX_THAWING_PERIOD + 1);
        _deprovision(0);

        // unstake
        _unstakeDuringLockingPeriod(tokensToUnstake, tokensThawing, 0, tokensThawingUntilBlock);
    }

    function testUnstake_RevertWhen_ZeroTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
        useThawAndDeprovision(amount, thawingPeriod)
    {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.unstake(0);
    }

    function testUnstake_RevertWhen_NoIdleStake(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
    {
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            amount,
            0
        );
        vm.expectRevert(expectedError);
        staking.unstake(amount);
    }

    function testUnstake_RevertWhen_NotDeprovision(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    )
        public
        useIndexer
        useProvision(amount, maxVerifierCut, thawingPeriod)
        useThawRequest(amount)
    {
        skip(thawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            amount,
            0
        );
        vm.expectRevert(expectedError);
        staking.unstake(amount);
    }
}