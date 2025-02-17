// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerGovernanceSubgraphService is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Governance_SetSubgraphService(address subgraphService) public useGovernor {
        vm.assume(subgraphService != address(0));
        _setSubgraphService(subgraphService);
    }

    function test_Governance_SetSubgraphService_RevertWhenZero() public useGovernor {
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidZeroAddress.selector));
        disputeManager.setSubgraphService(address(0));
    }
}
