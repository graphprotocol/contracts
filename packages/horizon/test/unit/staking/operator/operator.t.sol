// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingOperatorTest is HorizonStakingTest {
    /*
     * TESTS
     */

    function testOperator_SetOperator() public useIndexer {
        _setOperator(subgraphDataServiceAddress, users.operator, true);
    }

    function testOperator_RevertWhen_CallerIsServiceProvider() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCallerIsServiceProvider()");
        vm.expectRevert(expectedError);
        staking.setOperator(subgraphDataServiceAddress, users.indexer, true);
    }

    function testOperator_RemoveOperator() public useIndexer {
        _setOperator(subgraphDataServiceAddress, users.operator, true);
        _setOperator(subgraphDataServiceAddress, users.operator, false);
    }
}
