// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../../contracts/interfaces/internal/IHorizonStakingMain.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingSlashTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testSlash_Tokens(
        uint256 tokens,
        uint32 maxVerifierCut,
        uint256 slashTokens,
        uint256 verifierCutAmount
    ) public useIndexer useProvision(tokens, maxVerifierCut, 0) {
        slashTokens = bound(slashTokens, 1, tokens);
        uint256 maxVerifierTokens = (slashTokens * maxVerifierCut) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, verifierCutAmount);
    }

    function testSlash_Tokens_RevertWhen_TooManyVerifierTokens(
        uint256 tokens,
        uint32 maxVerifierCut,
        uint256 slashTokens,
        uint256 verifierCutAmount
    ) public useIndexer useProvision(tokens, maxVerifierCut, 0) {
        slashTokens = bound(slashTokens, 1, tokens);
        uint256 maxVerifierTokens = (slashTokens * maxVerifierCut) / MAX_PPM;
        vm.assume(verifierCutAmount > maxVerifierTokens);

        vm.startPrank(subgraphDataServiceAddress);
        vm.assume(slashTokens > 0);
        bytes memory expectedError = abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingTooManyTokens.selector,
            verifierCutAmount,
            maxVerifierTokens
        );
        vm.expectRevert(expectedError);
        staking.slash(users.indexer, slashTokens, verifierCutAmount, subgraphDataServiceAddress);
    }

    function testSlash_DelegationDisabled_SlashingOverProviderTokens(
        uint256 tokens,
        uint256 slashTokens,
        uint256 verifierCutAmount,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) {
        vm.assume(slashTokens > tokens);
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        verifierCutAmount = bound(verifierCutAmount, 0, MAX_PPM);
        vm.assume(verifierCutAmount <= tokens);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, verifierCutAmount);
    }

    function testSlash_DelegationEnabled_SlashingOverProviderTokens(
        uint256 tokens,
        uint256 slashTokens,
        uint256 verifierCutAmount,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) useDelegationSlashing {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        slashTokens = bound(slashTokens, tokens + 1, tokens + 1 + delegationTokens);
        verifierCutAmount = bound(verifierCutAmount, 0, tokens);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, verifierCutAmount);
    }

    function testSlash_OverProvisionSize(
        uint256 tokens,
        uint256 slashTokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) {
        delegationTokens = bound(delegationTokens, 0, MAX_STAKING_TOKENS);
        vm.assume(slashTokens > tokens + delegationTokens);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, 0);
    }

    function testSlash_RevertWhen_NoProvision(uint256 tokens, uint256 slashTokens) public useIndexer useStake(tokens) {
        vm.assume(slashTokens > 0);
        bytes memory expectedError = abi.encodeWithSelector(IHorizonStakingMain.HorizonStakingNoTokensToSlash.selector);
        vm.expectRevert(expectedError);
        vm.startPrank(subgraphDataServiceAddress);
        staking.slash(users.indexer, slashTokens, 0, subgraphDataServiceAddress);
    }

    function testSlash_Everything(
        uint256 tokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) useDelegationSlashing {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
    }

    function testSlash_Everything_WithUndelegation(
        uint256 tokens
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) useDelegationSlashing {
        uint256 delegationTokens = MAX_STAKING_TOKENS / 10;

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        // undelegate half shares so we have some thawing shares/tokens
        DelegationInternal memory delegation = _getStorage_Delegation(
            users.indexer,
            subgraphDataServiceAddress,
            users.delegator,
            false
        );
        resetPrank(users.delegator);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegation.shares / 2);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokens, 0);
    }

    function testSlash_RoundDown_TokensThawing_Provision(
        uint256 tokens,
        uint256 slashTokens,
        uint256 tokensToThaw
    ) public useIndexer {
        vm.assume(slashTokens <= tokens);
        vm.assume(tokensToThaw <= tokens);
        vm.assume(tokensToThaw > 0);

        _useProvision(subgraphDataServiceAddress, tokens, MAX_PPM, MAX_THAWING_PERIOD);
        _thaw(users.indexer, subgraphDataServiceAddress, tokensToThaw);

        Provision memory beforeProvision = staking.getProvision(users.indexer, subgraphDataServiceAddress);

        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, 0);

        Provision memory afterProvision = staking.getProvision(users.indexer, subgraphDataServiceAddress);
        assertEq(afterProvision.tokens, beforeProvision.tokens - slashTokens);
        assertEq(
            afterProvision.tokensThawing,
            (beforeProvision.tokensThawing * (beforeProvision.tokens - slashTokens)) / beforeProvision.tokens
        );
    }

    function testSlash_RoundDown_TokensThawing_Delegation(
        uint256 tokens,
        uint256 delegationTokensToSlash,
        uint256 delegationTokensToUndelegate
    ) public useIndexer useProvision(tokens, MAX_PPM, 0) useDelegationSlashing {
        uint256 delegationTokens = 10 ether;

        vm.assume(delegationTokensToSlash <= delegationTokens);
        vm.assume(delegationTokensToUndelegate <= delegationTokens);
        vm.assume(delegationTokensToUndelegate > 0);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);
        _undelegate(users.indexer, subgraphDataServiceAddress, delegationTokensToUndelegate);

        DelegationPool memory beforePool = staking.getDelegationPool(users.indexer, subgraphDataServiceAddress);

        // Slash
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, tokens + delegationTokensToSlash, 0);

        DelegationPool memory afterPool = staking.getDelegationPool(users.indexer, subgraphDataServiceAddress);
        assertEq(afterPool.tokens, beforePool.tokens - delegationTokensToSlash);
        assertEq(
            afterPool.tokensThawing,
            (beforePool.tokensThawing * (beforePool.tokens - delegationTokensToSlash)) / beforePool.tokens
        );
    }
}
