// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingOperatorTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testOperator_SetOperator() public useIndexer {
        _setOperator(users.operator, subgraphDataServiceAddress, true);
    }

    function testOperator_RevertWhen_CallerIsServiceProvider() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCallerIsServiceProvider()");
        vm.expectRevert(expectedError);
        staking.setOperator(users.indexer, subgraphDataServiceAddress, true);
    }

    function testOperator_RemoveOperator() public useIndexer {
        _setOperator(users.operator, subgraphDataServiceAddress, true);
        _setOperator(users.operator, subgraphDataServiceAddress, false);
    }
}