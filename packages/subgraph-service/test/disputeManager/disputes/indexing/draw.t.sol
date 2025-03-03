// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingDrawDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Indexing_Draw_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI32"));

        resetPrank(users.arbitrator);
        _drawDispute(disputeID);
    }

    function test_Indexing_Draw_RevertIf_CallerIsNotArbitrator(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // attempt to draw dispute as fisherman
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.drawDispute(disputeID);
    }
}
