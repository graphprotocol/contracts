// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingOperatorTest is HorizonStakingTest {

    /*
     * TESTS
     */

    function testOperator_SetOperator() public useOperator {
        assertTrue(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceAddress));
    }

    function testOperator_RevertWhen_CallerIsServiceProvider() public useIndexer {
        bytes memory expectedError = abi.encodeWithSignature("HorizonStakingCallerIsServiceProvider()");
        vm.expectRevert(expectedError);
        staking.setOperator(users.indexer, subgraphDataServiceAddress, true);
    }

    function testOperator_RemoveOperator() public useIndexer {
        staking.setOperator(users.operator, subgraphDataServiceAddress, true);
        assertTrue(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceAddress));

        staking.setOperator(users.operator, subgraphDataServiceAddress, false);
        assertFalse(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceAddress));
    }
}