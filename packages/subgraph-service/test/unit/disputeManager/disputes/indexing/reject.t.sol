// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingRejectDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Indexing_Reject_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        _rejectDispute(disputeID);
    }

    function test_Indexing_Reject_RevertIf_CallerIsNotArbitrator(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.rejectDispute(disputeID);
    }
}
