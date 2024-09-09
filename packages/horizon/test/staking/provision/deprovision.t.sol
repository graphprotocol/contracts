// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingDeprovisionTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testDeprovision_AllRequests(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 thawCount,
        uint256 deprovisionCount
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        thawCount = bound(thawCount, 1, MAX_THAW_REQUESTS);
        deprovisionCount = bound(deprovisionCount, 0, thawCount);
        vm.assume(amount >= thawCount); // ensure the provision has at least 1 token for each thaw step
        uint256 individualThawAmount = amount / thawCount;

        for (uint i = 0; i < thawCount; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, individualThawAmount);
        }

        skip(thawingPeriod + 1);

        _deprovision(users.indexer, subgraphDataServiceAddress, deprovisionCount);
    }

    function testDeprovision_ThawedRequests(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod,
        uint256 thawCount
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        thawCount = bound(thawCount, 2, MAX_THAW_REQUESTS);
        vm.assume(amount >= thawCount); // ensure the provision has at least 1 token for each thaw step
        uint256 individualThawAmount = amount / thawCount;

        for (uint i = 0; i < thawCount / 2; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, individualThawAmount);
        }

        skip(thawingPeriod + 1);

        for (uint i = 0; i < thawCount / 2; i++) {
            _thaw(users.indexer, subgraphDataServiceAddress, individualThawAmount);
        }

        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testDeprovision_OperatorMovingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) useOperator {
        _thaw(users.indexer, subgraphDataServiceAddress, amount);
        skip(thawingPeriod + 1);

        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testDeprovision_RevertWhen_OperatorNotAuthorized(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        _thaw(users.indexer, subgraphDataServiceAddress, amount);

        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            subgraphDataServiceAddress
        );
        vm.expectRevert(expectedError);
        staking.deprovision(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testDeprovision_RevertWhen_NoThawingTokens(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        staking.deprovision(users.indexer, subgraphDataServiceAddress, 0);
    }

    function testDeprovision_StillThawing(
        uint256 amount,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) public useIndexer useProvision(amount, maxVerifierCut, thawingPeriod) {
        vm.assume(thawingPeriod > 0);

        _thaw(users.indexer, subgraphDataServiceAddress, amount);

        _deprovision(users.indexer, subgraphDataServiceAddress, 0);
    }
}
