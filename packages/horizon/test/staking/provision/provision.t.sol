// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingProvisionTest is HorizonStakingTest {

    function testProvision_Create(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, amount);
    }

    function testProvision_RevertWhen_InsufficientTokens(uint256 amount) public useIndexer useStake(1000 ether) {
        amount = bound(amount, 0, MIN_PROVISION_SIZE - 1);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            amount,
            MIN_PROVISION_SIZE
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, 0, 0);
    }

    function testProvision_RevertWhen_MaxVerifierCutTooHigh(
        uint256 amount,
        uint32 maxVerifierCut
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(maxVerifierCut > MAX_MAX_VERIFIER_CUT);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInvalidMaxVerifierCut(uint32,uint32)",
            maxVerifierCut,
            MAX_MAX_VERIFIER_CUT
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, maxVerifierCut, 0);
    }

    function testProvision_RevertWhen_ThawingPeriodTooHigh(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(thawingPeriod > MAX_THAWING_PERIOD);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInvalidThawingPeriod(uint64,uint64)",
            thawingPeriod,
            MAX_THAWING_PERIOD
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, 0, thawingPeriod);
    }

    function testProvision_RevertWhen_ThereIsNoIdleStake(
        uint256 amount,
        uint256 provisionTokens
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(provisionTokens > amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            provisionTokens,
            amount
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, provisionTokens, 0, 0);
    }

    function testProvision_OperatorAddTokensToProvision(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 tokensToAdd
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        tokensToAdd = bound(tokensToAdd, 1, type(uint256).max - amount);
        // Set operator
        staking.setOperator(users.operator, subgraphDataServiceAddress, true);

        // Add more tokens to the provision
        vm.startPrank(users.operator);
        _stakeTo(users.indexer, tokensToAdd);
        staking.addToProvision(users.indexer, subgraphDataServiceAddress, tokensToAdd);

        uint256 provisionTokens = staking.getProviderTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(provisionTokens, amount + tokensToAdd);
    }

    function testProvision_RevertWhen_OperatorNotAuthorized(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)", 
            users.operator,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, maxVerifierCut, thawingPeriod);
    }
}