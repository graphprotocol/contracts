// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingSlashTest is HorizonStakingTest {

    /*
     * MODIFIERS
     */

    modifier useDelegationSlashing(bool enabled) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        vm.startPrank(users.governor);
        staking.setDelegationSlashingEnabled(enabled);
        vm.startPrank(msgSender);
        _;
    }

    /*
     * HELPERS
     */

    function _slash(uint256 amount, uint256 verifierCutAmount) private {
        staking.slash(users.indexer, amount, verifierCutAmount, subgraphDataServiceAddress);
    }

    /*
     * TESTS
     */

    function testSlash_Tokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint256 slashAmount,
        uint256 verifierCutAmount
    ) public useIndexer useProvision(amount, maxVerifierCut, 0) {
        verifierCutAmount = bound(verifierCutAmount, 0, maxVerifierCut);
        slashAmount = bound(slashAmount, 1, amount);
        uint256 maxVerifierTokens = (slashAmount * maxVerifierCut) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);
        
        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, verifierCutAmount);
        
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, amount - slashAmount);

        uint256 verifierTokens = token.balanceOf(subgraphDataServiceAddress);
        assertEq(verifierTokens, verifierCutAmount);
    }

    function testSlash_RevertWhen_TooManyTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint256 verifierCutAmount
    ) public useIndexer useProvision(amount, maxVerifierCut, 0) {
        uint256 maxVerifierTokens = (amount * maxVerifierCut) / MAX_PPM;
        verifierCutAmount = bound(verifierCutAmount, maxVerifierTokens + 1, MAX_STAKING_TOKENS);

        vm.startPrank(subgraphDataServiceAddress);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingTooManyTokens(uint256,uint256)",
            verifierCutAmount,
            maxVerifierTokens
        );
        vm.expectRevert(expectedError);
        _slash(amount, verifierCutAmount);
    }

    function testSlash_DelegationDisabled_SlashingOverProvisionTokens(
        uint256 amount,
        uint256 slashAmount,
        uint256 verifierCutAmount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, MAX_MAX_VERIFIER_CUT, 0) useDelegationSlashing(false) {
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        slashAmount = bound(slashAmount, amount + 1, amount + delegationAmount);
        verifierCutAmount = bound(verifierCutAmount, 0, MAX_MAX_VERIFIER_CUT);
        uint256 maxVerifierTokens = (amount * MAX_MAX_VERIFIER_CUT) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceAddress);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, verifierCutAmount);

        uint256 provisionProviderTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionProviderTokens, 0 ether);

        uint256 verifierTokens = token.balanceOf(address(subgraphDataServiceAddress));
        assertEq(verifierTokens, verifierCutAmount);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        // No slashing occurred for delegation
        assertEq(delegatedTokens, delegationAmount);
    }

    function testSlash_DelegationEnabled_SlashingOverProvisionTokens(
        uint256 amount,
        uint256 slashAmount,
        uint256 verifierCutAmount,
        uint256 delegationAmount
    ) public useIndexer useProvision(amount, MAX_MAX_VERIFIER_CUT, 0) useDelegationSlashing(true) {
        delegationAmount = bound(delegationAmount, MIN_DELEGATION, MAX_STAKING_TOKENS);
        slashAmount = bound(slashAmount, amount + 1, amount + delegationAmount);
        verifierCutAmount = bound(verifierCutAmount, 0, MAX_MAX_VERIFIER_CUT);
        uint256 maxVerifierTokens = (amount * MAX_MAX_VERIFIER_CUT) / MAX_PPM;
        vm.assume(verifierCutAmount <= maxVerifierTokens);

        resetPrank(users.delegator);
        _delegate(delegationAmount, subgraphDataServiceAddress);

        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, verifierCutAmount);
        
        uint256 provisionProviderTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionProviderTokens, 0 ether);

        uint256 verifierTokens = token.balanceOf(address(subgraphDataServiceAddress));
        assertEq(verifierTokens, verifierCutAmount);

        uint256 delegatedTokens = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        uint256 slashedDelegation = slashAmount - amount;
        assertEq(delegatedTokens, delegationAmount - slashedDelegation);
    }

    function testSlash_RevertWhen_NoProvision(
        uint256 amount,
        uint256 slashAmount
    ) public useIndexer useStake(amount) {
        slashAmount = bound(slashAmount, 1, amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            0 ether,
            slashAmount
        );
        vm.expectRevert(expectedError);
        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, 0);
    }
}