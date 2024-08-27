// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDeprovisionTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testDeprovision_AllRequests(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        skip(thawingPeriod + 1);

        // nThawRequests == 0 removes all thaw requests
        _deprovision(0);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, amount);
    }

    function testDeprovision_FirstRequestOnly(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.assume(amount > 1);
        thawAmount = bound(thawAmount, 2, amount);
        uint256 thawAmount1 = thawAmount / 2;
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount1);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount - thawAmount1);

        skip(thawingPeriod + 1);

        _deprovision(1);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, thawAmount1);
    }

    function testDeprovision_OperatorMovingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useOperator useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        skip(thawingPeriod + 1);

        _deprovision(0);
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
        _deprovision(0);
    }
    function testDeprovision_RevertWhen_NoThawingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        _deprovision(0);
    }

    function testDeprovision_StillThawing(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useThawRequest(amount) {
        vm.assume(thawingPeriod > 0);
        _deprovision(0);
        uint256 idleStake = staking.getIdleStake(users.indexer);
        assertEq(idleStake, 0);
    }
}