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
    ) public useIndexer useProvision(tokens, MAX_MAX_VERIFIER_CUT, 0) {
        vm.assume(slashTokens > tokens);
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        verifierCutAmount = bound(verifierCutAmount, 0, MAX_MAX_VERIFIER_CUT);
        uint256 maxVerifierTokens = (tokens * MAX_MAX_VERIFIER_CUT) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);

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
    ) public useIndexer useProvision(tokens, MAX_MAX_VERIFIER_CUT, 0) useDelegationSlashing() {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        slashTokens = bound(slashTokens, tokens + 1, tokens + delegationTokens);
        verifierCutAmount = bound(verifierCutAmount, 0, MAX_MAX_VERIFIER_CUT);
        uint256 maxVerifierTokens = (tokens * MAX_MAX_VERIFIER_CUT) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, verifierCutAmount);
    }

    function testSlash_OverProvisionSize(
        uint256 tokens,
        uint256 slashTokens,
        uint256 delegationTokens
    ) public useIndexer useProvision(tokens, MAX_MAX_VERIFIER_CUT, 0) {
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        vm.assume(slashTokens > tokens + delegationTokens);
        
        vm.startPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, slashTokens, 0);
    }

    function testSlash_RevertWhen_NoProvision(
        uint256 tokens,
        uint256 slashTokens
    ) public useIndexer useStake(tokens) {
        vm.assume(slashTokens > 0);
        bytes memory expectedError = abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInsufficientTokens.selector,
            0,
            slashTokens
        );
        vm.expectRevert(expectedError);
        vm.startPrank(subgraphDataServiceAddress);
        staking.slash(users.indexer, slashTokens, 0, subgraphDataServiceAddress);
    }
}