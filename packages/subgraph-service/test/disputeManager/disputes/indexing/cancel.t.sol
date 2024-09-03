// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingCancelDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Indexing_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"));

        _cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_RevertIf_DisputePeriodNotOver(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID =_createIndexingDispute(allocationID, bytes32("POI1"));

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
