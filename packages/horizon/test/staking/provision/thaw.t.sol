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

        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_MultipleRequests(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawCount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        thawCount = bound(thawCount, 1, MAX_THAW_REQUESTS);
        vm.assume(amount >= thawCount); // ensure the provision has at least 1 token for each thaw step
        uint256 individualThawAmount = amount / thawCount;

        for (uint i = 0; i < thawCount; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, individualThawAmount);
        }
    }

    function testThaw_OperatorCanStartThawing(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, thawingPeriod) useOperator {
        _thaw(users.indexer, subgraphDataServiceAddress, amount);
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
        staking.thaw(users.indexer, subgraphDataServiceAddress, amount);
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
        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_RevertWhen_OverMaxThawRequests(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        vm.assume(amount >= MAX_THAW_REQUESTS + 1);
        thawAmount = bound(thawAmount, 1, amount / (MAX_THAW_REQUESTS + 1));

        for (uint256 i = 0; i < MAX_THAW_REQUESTS; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        }

        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingTooManyThawRequests()");
        vm.expectRevert(expectedError);
        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_RevertWhen_ThawingZeroTokens(
        uint256 amount,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        uint256 thawAmount = 0 ether;
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }
}
