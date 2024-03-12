// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import { SimpleTest } from "../contracts/SubgraphService.sol";

contract ContractTest is Test {
    SimpleTest simpleTest;

    function setUp() public {
        simpleTest = new SimpleTest();
    }

    function test_NumberIs42() public {
        assertEq(simpleTest.test(), 42);
    }

}