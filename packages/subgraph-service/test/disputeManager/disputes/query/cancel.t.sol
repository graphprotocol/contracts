// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCancelDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createQueryDispute();

        // skip to end of dispute period
        skip(disputePeriod + 1);

        resetPrank(users.fisherman);
        disputeManager.cancelDispute(disputeID);

        assertEq(token.balanceOf(users.fisherman), fishermanPreviousBalance, "Fisherman should receive their deposit back.");
    }

    function test_Query_Cancel_RevertIf_CallerIsNotFisherman(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = _createQueryDispute();

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Query_Cancel_RevertIf_DisputePeriodNotOver(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = _createQueryDispute();

        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
