// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

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

        _reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 0);
    }

    function testReprovision_OperatorMovingTokens(
        uint64 thawingPeriod,
        uint256 provisionAmount
    ) public useOperator useProvision(provisionAmount, 0, thawingPeriod) {
        _thaw(users.indexer, subgraphDataServiceAddress, provisionAmount);
        skip(thawingPeriod + 1);

        // Switch to indexer to set operator for new data service
        vm.startPrank(users.indexer);
        _setOperator(newDataService, users.operator, true);

        // Switch back to operator
        vm.startPrank(users.operator);
        _createProvision(users.indexer, newDataService, 1 ether, 0, thawingPeriod);
        _reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 0);
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
            users.indexer,
            newDataService,
            users.operator
        );
        vm.expectRevert(expectedError);
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 0);
    }

    function testReprovision_RevertWhen_NoThawingTokens(uint256 amount) public useIndexer useProvision(amount, 0, 0) {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingNothingThawing()");
        vm.expectRevert(expectedError);
        staking.reprovision(users.indexer, subgraphDataServiceAddress, newDataService, 0);
    }
}
