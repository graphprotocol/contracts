// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { SubgraphServiceSharedTest } from "../shared/SubgraphServiceShared.t.sol";

contract SubgraphServiceTest is SubgraphServiceSharedTest {

    /*
     * VARIABLES
     */

    /*
     * MODIFIERS
     */

    modifier useOperator {
        vm.startPrank(users.operator);
        _;
        vm.stopPrank();
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
    }

    /*
     * HELPERS
     */

}