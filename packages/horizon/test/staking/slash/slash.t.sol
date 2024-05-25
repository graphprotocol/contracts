// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingSlashTest is HorizonStakingTest {

    modifier useDelegationSlashingDisabled() {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        vm.startPrank(users.governor);
        staking.setDelegationSlashingEnabled(false);
        vm.startPrank(msgSender);
        _;
    }

    function _slash(uint256 amount, uint256 verifierCutAmount) private {
        staking.slash(users.indexer, amount, verifierCutAmount, subgraphDataServiceAddress);
    }

    function testSlash_Tokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint256 slashAmount,
        uint256 verifierCutAmount
    ) public useIndexer useProvision(amount, maxVerifierCut, 0) {
        verifierCutAmount = bound(verifierCutAmount, 0, maxVerifierCut);

        // TODO: when slashing for low amounts there's an arithmetic underflow
        slashAmount = bound(slashAmount, MIN_PROVISION_SIZE, amount);
        
        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, verifierCutAmount);
        
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, amount - slashAmount);

        uint256 verifierTokens = token.balanceOf(subgraphDataServiceAddress);
        assertEq(verifierTokens, verifierCutAmount);
    }

    // TODO: Should be re-enabled when slashin is fixed to count for delegated  tokens
    // function testSlash_DelegationDisabled_SlashingOverProvisionTokens(
    //     uint256 amount,
    //     uint256 slashAmount,
    //     uint256 verifierCutAmount,
    //     uint256 delegationAmount
    // ) public useIndexer useProvision(amount, 100000, 0) useDelegationSlashingDisabled {
    //     vm.assume(slashAmount > amount);
    //     vm.assume(delegationAmount > 0);
    //     uint32 delegationRatio = 5;

    //     vm.stopPrank();
    //     vm.startPrank(users.delegator);
    //     _delegate(delegationAmount);

    //     vm.startPrank(subgraphDataServiceAddress);
    //     _slash(slashAmount, verifierCutAmount);
        
    //     uint256 provisionProviderTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
    //     assertEq(provisionProviderTokens, 0 ether);

    //     uint256 verifierTokens = token.balanceOf(address(subgraphDataServiceAddress));
    //     assertEq(verifierTokens, verifierCutAmount);

    //     uint256 delegatedTokens = staking.getTokensAvailable(users.indexer, subgraphDataServiceAddress, delegationRatio);
    //     assertEq(delegatedTokens, delegationAmount);
    // }

    function testSlash_RevertWhen_NoProvision(
        uint256 amount,
        uint256 slashAmount
    ) public useIndexer useStake(amount) {
        // TODO: when slashing for low amounts there's an arithmetic underflow
        slashAmount = bound(slashAmount, MIN_PROVISION_SIZE, amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            slashAmount, 
            0 ether
        );
        vm.expectRevert(expectedError);
        vm.startPrank(subgraphDataServiceAddress);
        _slash(slashAmount, 0);
    }
}