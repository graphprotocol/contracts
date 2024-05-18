// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../GraphBase.t.sol";

contract GraphDeploymentsTest is GraphBaseTest {

    function testDeployments() public view {
        assertEq(address(escrow.GRAPH_PAYMENTS()), address(payments));
        assertEq(address(escrow.GRAPH_TOKEN()), address(token));
        assertEq(address(payments.STAKING()), address(staking));
        assertEq(address(payments.GRAPH_ESCROW()), address(escrow));
        assertEq(address(payments.GRAPH_TOKEN()), address(token));
    }
}
