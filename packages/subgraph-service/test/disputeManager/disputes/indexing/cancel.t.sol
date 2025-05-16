// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingCancelDisputeTest is DisputeManagerTest {
    /*
     * TESTS
     */

    function test_Indexing_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // skip to end of dispute period
        uint256 disputePeriod = disputeManager.disputePeriod();
        skip(disputePeriod + 1);

        _cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_RevertIf_DisputePeriodNotOver(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_After_DisputePeriodIncreased(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // change the dispute period to a higher value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod * 2));

        // skip to end of old dispute period
        skip(oldDisputePeriod + 1);

        // should be able to cancel
        resetPrank(users.fisherman);
        _cancelDispute(disputeID);
    }

    function test_Indexing_Cancel_After_DisputePeriodDecreased(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // change the dispute period to a lower value
        uint256 oldDisputePeriod = disputeManager.disputePeriod();
        resetPrank(users.governor);
        disputeManager.setDisputePeriod(uint64(oldDisputePeriod / 2));

        // skip to end of new dispute period
        skip(oldDisputePeriod / 2 + 1);

        // should not be able to cancel
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
