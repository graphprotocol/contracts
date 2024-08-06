// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryDrawDisputeTest is DisputeManagerTest {

    /*
     * TESTS
     */

    function test_Query_Draw_Dispute(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createQueryDispute();

        resetPrank(users.arbitrator);
        disputeManager.drawDispute(disputeID);

        assertEq(token.balanceOf(users.fisherman), fishermanPreviousBalance, "Fisherman should receive their deposit back.");
    }

    function test_Query_Draw_RevertIf_CallerIsNotArbitrator(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = _createQueryDispute();

        // attempt to draw dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.drawDispute(disputeID);
    }
}
