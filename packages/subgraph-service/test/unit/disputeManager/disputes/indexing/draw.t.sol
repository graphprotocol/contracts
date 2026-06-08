// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingDrawDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Indexing_Draw_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI32"), block.number);

        resetPrank(users.arbitrator);
        _drawDispute(disputeId);
    }

    function test_Indexing_Draw_RevertIf_CallerIsNotArbitrator(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        // attempt to draw dispute as fisherman
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.drawDispute(disputeId);
    }
}
