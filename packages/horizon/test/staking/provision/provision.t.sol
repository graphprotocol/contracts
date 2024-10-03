// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingProvisionTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testProvision_Create(uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        maxVerifierCut = uint32(bound(maxVerifierCut, 0, MAX_MAX_VERIFIER_CUT));
        thawingPeriod = uint32(bound(thawingPeriod, 0, MAX_THAWING_PERIOD));

        _createProvision(users.indexer, subgraphDataServiceAddress, tokens, maxVerifierCut, thawingPeriod);
    }

    function testProvision_RevertWhen_ZeroTokens() public useIndexer useStake(1000 ether) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, 0, 0, 0);
    }

    function testProvision_RevertWhen_MaxVerifierCutTooHigh(
        uint256 amount,
        uint32 maxVerifierCut
    ) public useIndexer useStake(amount) {
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
        vm.assume(provisionTokens > amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            provisionTokens,
            amount
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, provisionTokens, 0, 0);
    }

    function testProvision_RevertWhen_AlreadyExists(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount / 2, maxVerifierCut, thawingPeriod) {
        resetPrank(users.indexer);

        token.approve(address(staking), amount / 2);
        _stake(amount / 2);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingProvisionAlreadyExists()");
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount / 2, maxVerifierCut, thawingPeriod);
    }

    function testProvision_OperatorAddTokensToProvision(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 tokensToAdd
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useOperator {
        tokensToAdd = bound(tokensToAdd, 1, MAX_STAKING_TOKENS);

        // Add more tokens to the provision
        _stakeTo(users.indexer, tokensToAdd);
        _addToProvision(users.indexer, subgraphDataServiceAddress, tokensToAdd);
    }

    function testProvision_RevertWhen_OperatorNotAuthorized(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.indexer,
            users.operator,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.provision(users.indexer, subgraphDataServiceAddress, amount, maxVerifierCut, thawingPeriod);
    }
}
