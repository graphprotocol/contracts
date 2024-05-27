// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDeprovisionTest is HorizonStakingTest {

    function testDeprovision_Tokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        skip(thawingPeriod + 1);

        _deprovision(amount);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, amount);
    }

    function testDeprovision_OperatorMovingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useOperator useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        skip(thawingPeriod + 1);

        _deprovision(amount);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, amount);
    }

    function testDeprovision_RevertWhen_OperatorNotAuthorized(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        _deprovision(amount);
    }

    function testDeprovision_RevertWhen_ZeroTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        _deprovision(0);
    }

    function testDeprovision_RevertWhen_NoThawingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCannotFulfillThawRequest()");
        vm.expectRevert(expectedError);
        _deprovision(amount);
    }

    function testDeprovision_RevertWhen_StillThawing(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        vm.assume(thawingPeriod > 0);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingStillThawing(uint256)",
            block.timestamp + thawingPeriod
        );
        vm.expectRevert(expectedError);
        _deprovision(amount);
    }

    function testDeprovision_RevertWhen_NotEnoughThawedTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 deprovisionAmount
    ) public  useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.assume(deprovisionAmount > amount);
        skip(thawingPeriod + 1);

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCannotFulfillThawRequest()");
        vm.expectRevert(expectedError);
        _deprovision(deprovisionAmount);
    }
}