// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Query_Accept_Dispute(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        uint256 fishermanPreviousBalance = token.balanceOf(users.fisherman);
        bytes32 disputeID = _createQueryDispute();

        resetPrank(users.arbitrator);
        disputeManager.acceptDispute(disputeID, tokensSlash);

        uint256 fishermanReward = tokensSlash.mulPPM(fishermanRewardPercentage);
        uint256 fishermanExpectedBalance = fishermanPreviousBalance + fishermanReward;
        assertEq(token.balanceOf(users.fisherman), fishermanExpectedBalance, "Fisherman should receive 50% of slashed tokens.");
    }

    function test_Query_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        bytes32 disputeID = _createQueryDispute();

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Query_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, uint256(maxSlashingPercentage).mulPPM(tokens) + 1, type(uint256).max);
        bytes32 disputeID = _createQueryDispute();

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector, 
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }
}
