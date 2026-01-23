// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
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
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Dispute_Accept_RevertIf_SlashZeroTokens(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI101"), block.number);

        // attempt to accept dispute with 0 tokens slashed
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens);
        vm.expectRevert(
            abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 0, maxTokensToSlash)
        );
        disputeManager.acceptDispute(disputeId, 0);
    }

    function test_Dispute_Reject_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.rejectDispute(disputeId);
    }

    function test_Dispute_Draw_RevertIf_DisputeDoesNotExist(uint256 tokens) public useIndexer useAllocation(tokens) {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = bytes32("0x0");

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerInvalidDispute.selector, disputeId));
        disputeManager.drawDispute(disputeId);
    }
}
