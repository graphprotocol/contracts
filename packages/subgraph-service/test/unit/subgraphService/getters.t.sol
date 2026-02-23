// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { SubgraphServiceTest } from "./SubgraphService.t.sol";

contract SubgraphServiceGettersTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_GetDisputeManager() public view {
        address result = subgraphService.getDisputeManager();
        assertEq(result, address(disputeManager));
    }

    function test_GetGraphTallyCollector() public view {
        address result = subgraphService.getGraphTallyCollector();
        assertEq(result, address(graphTallyCollector));
    }

    function test_GetCuration() public view {
        address result = subgraphService.getCuration();
        assertEq(result, address(curation));
    }
}
