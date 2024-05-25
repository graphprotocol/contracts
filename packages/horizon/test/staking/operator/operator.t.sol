// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";

contract HorizonStakingOperatorTest is HorizonStakingTest {

    function testOperator_SetOperator() public useIndexer {
        staking.setOperator(users.operator, subgraphDataServiceAddress, true);
        assertTrue(staking.isAuthorized(users.operator, users.indexer, subgraphDataServiceAddress));
    }
}