// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingTypes } from "../../../../contracts/interfaces/internal/IHorizonStakingTypes.sol";
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
        thawCount = bound(thawCount, 1, 100);
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
            users.indexer,
            subgraphDataServiceAddress,
            users.operator
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

    function testThaw_RevertWhen_OverMaxThawRequests() public useIndexer useProvision(10000 ether, 0, 0) {
        uint256 thawAmount = 1 ether;

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

    function testThaw_RevertWhen_ProvisionFullySlashed(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        thawAmount = bound(thawAmount, 1, amount);

        // slash all of it
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, amount, 0);

        // Attempt to thaw on a provision that has been fully slashed
        resetPrank(users.indexer);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientTokens(uint256,uint256)",
            0,
            thawAmount
        );
        vm.expectRevert(expectedError);
        staking.thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_AfterResetingThawingPool(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        // thaw some funds so there are some shares thawing and tokens thawing
        thawAmount = bound(thawAmount, 1, amount);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);

        // slash all of it
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, amount, 0);

        // put some funds back in
        resetPrank(users.indexer);
        _stake(amount);
        _addToProvision(users.indexer, subgraphDataServiceAddress, amount);

        // we should be able to thaw again
        resetPrank(users.indexer);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
    }

    function testThaw_GetThawedTokens(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawSteps
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        thawSteps = bound(thawSteps, 1, 10);

        uint256 thawAmount = amount / thawSteps;
        vm.assume(thawAmount > 0);
        for (uint256 i = 0; i < thawSteps; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);
        }

        skip(thawingPeriod + 1);

        uint256 thawedTokens = staking.getThawedTokens(
            ThawRequestType.Provision,
            users.indexer,
            subgraphDataServiceAddress,
            users.indexer
        );
        vm.assertEq(thawedTokens, thawAmount * thawSteps);
    }

    function testThaw_GetThawedTokens_AfterProvisionFullySlashed(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        // thaw some funds so there are some shares thawing and tokens thawing
        thawAmount = bound(thawAmount, 1, amount);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);

        // skip to after the thawing period has passed
        skip(thawingPeriod + 1);

        // slash all of it
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, amount, 0);

        // get the thawed tokens - should be zero now as the pool was reset
        uint256 thawedTokens = staking.getThawedTokens(
            ThawRequestType.Provision,
            users.indexer,
            subgraphDataServiceAddress,
            users.indexer
        );
        vm.assertEq(thawedTokens, 0);
    }

    function testThaw_GetThawedTokens_AfterRecoveringProvision(
        uint256 amount,
        uint64 thawingPeriod,
        uint256 thawAmount
    ) public useIndexer useProvision(amount, 0, thawingPeriod) {
        // thaw some funds so there are some shares thawing and tokens thawing
        thawAmount = bound(thawAmount, 1, amount);
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);

        // skip to after the thawing period has passed
        skip(thawingPeriod + 1);

        // slash all of it
        resetPrank(subgraphDataServiceAddress);
        _slash(users.indexer, subgraphDataServiceAddress, amount, 0);

        // get the thawed tokens - should be zero now as the pool was reset
        uint256 thawedTokens = staking.getThawedTokens(
            ThawRequestType.Provision,
            users.indexer,
            subgraphDataServiceAddress,
            users.indexer
        );
        vm.assertEq(thawedTokens, 0);

        // put some funds back in
        resetPrank(users.indexer);
        _stake(amount);
        _addToProvision(users.indexer, subgraphDataServiceAddress, amount);

        // thaw some more funds
        _thaw(users.indexer, subgraphDataServiceAddress, thawAmount);

        // skip to after the thawing period has passed
        skip(block.timestamp + thawingPeriod + 1);

        // get the thawed tokens - should be the amount we thawed
        thawedTokens = staking.getThawedTokens(
            ThawRequestType.Provision,
            users.indexer,
            subgraphDataServiceAddress,
            users.indexer
        );
        vm.assertEq(thawedTokens, thawAmount);
    }
}
