// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingReprovisionTest is HorizonStakingTest {
    /*
     * VARIABLES
     */

    address private newDataService = makeAddr("newDataService");

    /*
     * TESTS
     */

    function testReprovision_MovingTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount
    ) public useIndexer useProvision(provisionAmount, 0, thawingPeriod) {
        _thaw(users.indexer, subgraphDataServiceAddress, provisionAmount);
        skip(thawingPeriod + 1);

        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);

        _reprovision(users.indexer, subgraphDataServiceAddress, newDataService, provisionAmount, 0);
    }

    function testReprovision_TokensOverThawingTokens() public useIndexer {
        uint64 thawingPeriod = 1 days;

        // create provision A, thaw 10 ether, skip time so they are fully thawed
        _createProvision(users.indexer, subgraphDataServiceAddress, 100 ether, 0, thawingPeriod);
        _thaw(users.indexer, subgraphDataServiceAddress, 10 ether);
        skip(thawingPeriod + 1);

        // create provision B
        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);

        // reprovision 100 ether from A to B
        // this should revert because there are only 10 ether that thawed and the service provider
        // doesn't have additional idle stake to cover the difference
        vm.expectRevert();
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 100 ether, 0);

        // now add some idle stake and try again, it should not revert
        _stake(100 ether);
        _reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 100 ether, 0);
    }

    function testReprovision_OperatorMovingTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount
    ) public useOperator useProvision(provisionAmount, 0, thawingPeriod) {
        _thaw(users.indexer, subgraphDataServiceAddress, provisionAmount);
        skip(thawingPeriod + 1);

        // Switch to indexer to set operator for new data service
        vm.startPrank(users.indexer);
        _setOperator(users.operator, newDataService, true);

        // Switch back to operator
        vm.startPrank(users.operator);
        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);
        _reprovision(users.indexer, subgraphDataServiceAddress, newDataService, provisionAmount, 0);
    }

    function testReprovision_RevertWhen_OperatorNotAuthorizedForNewDataService(
        uint256 provisionAmount
    ) public useOperator useProvision(provisionAmount, 0, 0) {
        _thaw(users.indexer, subgraphDataServiceAddress, provisionAmount);

        // Switch to indexer to create new provision
        vm.startPrank(users.indexer);
        _createProvision(users.indexer, newDataService, 1 ether, 0, 0);

        // Switch back to operator
        vm.startPrank(users.operator);
        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingNotAuthorized(address,address,address)",
            users.operator,
            users.indexer,
            newDataService
        );
        vm.expectRevert(expectedError);
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, provisionAmount, 0);
    }

    function testReprovision_RevertWhen_NoThawingTokens(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, amount, 0);
    }

    function testReprovision_RevertWhen_StillThawing(
        uint64 thawingPeriod,
        uint256 provisionAmount
    ) public useIndexer useProvision(provisionAmount, 0, thawingPeriod) {
        vm.assume(thawingPeriod > 0);
        _thaw(users.indexer, subgraphDataServiceAddress, provisionAmount);

        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);

        bytes memory expectedError = abi.encodeWithSignature(
            "HorizonStakingInsufficientIdleStake(uint256,uint256)",
            provisionAmount,
            0
        );
        vm.expectRevert(expectedError);
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, provisionAmount, 0);
    }
}
