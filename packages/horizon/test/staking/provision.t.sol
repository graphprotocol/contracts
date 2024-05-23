// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "./HorizonStaking.t.sol";

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
        vm.assume(amount < MIN_PROVISION_SIZE);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInsufficientTokens(uint256,uint256)", MIN_PROVISION_SIZE, amount);
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, 0, 0);
    }

    function testProvision_RevertWhen_MaxVerifierCutTooHigh(
        uint256 amount,
        uint32 maxVerifierCut
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(maxVerifierCut > MAX_MAX_VERIFIER_CUT);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingMaxVerifierCutExceeded(uint32,uint32)", MAX_MAX_VERIFIER_CUT, maxVerifierCut);
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, maxVerifierCut, 0);
    }

    function testProvision_RevertWhen_ThawingPeriodTooHigh(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(thawingPeriod > STAKING_MAX_THAWING_PERIOD);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingMaxThawingPeriodExceeded(uint64,uint64)", STAKING_MAX_THAWING_PERIOD, thawingPeriod);
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, 0, thawingPeriod);
    }

    function testProvision_RevertWhen_ThereIsNoIdleStake(
        uint256 amount,
        uint256 provisionTokens
    ) public useIndexer useStake(amount) {
        vm.assume(amount > MIN_PROVISION_SIZE);
        vm.assume(provisionTokens > amount);
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInsufficientCapacity()");
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, provisionTokens, 0, 0);
    }

    function testProvision_OperatorAddTokensToProvision(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 tokensToAdd
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.assume(tokensToAdd > 0);
        vm.assume(amount <= type(uint256).max - tokensToAdd);
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