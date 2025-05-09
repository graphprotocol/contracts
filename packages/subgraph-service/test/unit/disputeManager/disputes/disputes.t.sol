// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Dispute_Accept_RevertIf_DisputeDoesNotExist(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        bytes32 disputeID = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeID));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Dispute_Accept_RevertIf_SlashZeroTokens(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI101"));

        // attempt to accept dispute with 0 tokens slashed
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(tokens);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 0, maxTokensToSlash)
        );
        disputeManager.acceptDispute(disputeID, 0);
    }

    function test_Dispute_Reject_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeID));
        disputeManager.rejectDispute(disputeID);
    }

    function test_Dispute_Draw_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        bytes32 disputeID = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeID));
        disputeManager.drawDispute(disputeID);
    }
}
