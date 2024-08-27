// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IHorizonStakingTypes } from "../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingThawTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testThaw_Tokens(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        thawAmount = bound(thawAmount, 1, amount);
        bytes32 expectedThawRequestId = keccak256(
            abi.encodePacked(users.indexer, subgraphDataServiceAddress, users.indexer, uint256(0))
        );
        bytes32 thawRequestId = _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        assertEq(thawRequestId, expectedThawRequestId);

        ThawRequest memory thawRequest = staking.getThawRequest(expectedThawRequestId);
        assertEq(thawRequest.shares, thawAmount);
        assertEq(thawRequest.thawingUntil, block.timestamp + thawingPeriod);
    }

    function testThaw_MultipleRequests(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount,
        uint256 thawAmount2
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        vm.assume(amount > 1);
        thawAmount = bound(thawAmount, 1, amount - 1);
        thawAmount2 = bound(thawAmount2, 1, amount - thawAmount);
        bytes32 thawRequestId = _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        bytes32 thawRequestId2 = _thaw(users.indexer, subgraphDataServiceAddress, thawAmount2);

        ThawRequest memory thawRequest = staking.getThawRequest(thawRequestId);
        assertEq(thawRequest.shares, thawAmount);
        assertEq(thawRequest.thawingUntil, block.timestamp + thawingPeriod);
        assertEq(thawRequest.next, thawRequestId2);

        ThawRequest memory thawRequest2 = staking.getThawRequest(thawRequestId2);
        assertEq(thawRequest2.shares, thawAmount2);
        assertEq(thawRequest2.thawingUntil, block.timestamp + thawingPeriod);
    }

    function testThaw_OperatorCanStartThawing(
        uint256 amount,
        uint64 thawingPeriod
    ) public useOperator useProvision(amount, 0, thawingPeriod) {
        bytes32 thawRequestId = _thaw(users.indexer, subgraphDataServiceAddress, amount);

        ThawRequest memory thawRequest = staking.getThawRequest(thawRequestId);
        assertEq(thawRequest.shares, amount);
        assertEq(thawRequest.thawingUntil, block.timestamp + thawingPeriod);
    }

    function testThaw_RevertWhen_OperatorNotAuthorized(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        _thaw(users.indexer, subgraphDataServiceAddress, amount);
    }

    function testThaw_RevertWhen_InsufficientTokensAvailable(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        vm.assume(thawAmount > amount);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            amount,
            thawAmount
        );
        vm.expectRevert(expectedError);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_RevertWhen_OverMaxThawRequests(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        vm.assume(amount >= MAX_THAW_REQUESTS + 1);
        thawAmount = bound(thawAmount, 1, amount / (MAX_THAW_REQUESTS + 1));

        for (uint256 i = 0; i < 100; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        }

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingTooManyThawRequests()");
        vm.expectRevert(expectedError);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_RevertWhen_ThawingZeroTokens(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        uint256 thawAmount = 0 ether;
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }
}
