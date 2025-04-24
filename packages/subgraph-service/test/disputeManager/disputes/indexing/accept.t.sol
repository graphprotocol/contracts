// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Indexing_Accept_Dispute(uint256 tokens, uint256 tokensSlash) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        // clear subgraph service address from storage
        _setStorage_SubgraphService(address(0));

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_Dispute_OptParam(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(maxSlashingPercentage).mulPPM(tokens));

        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        tokensSlash = bound(tokensSlash, uint256(maxSlashingPercentage).mulPPM(tokens) + 1, type(uint256).max);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI101"));

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

    function test_Indexing_Accept_Dispute_WithDelegation(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        tokensSlash = bound(
            tokensSlash,
            1,
            uint256(maxSlashingPercentage).mulPPM(_calculateStakeSnapshot(tokens, tokensDelegated))
        );

        // Initial dispute with delegation slashing disabled
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI1"));

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_RevertWhen_SlashingOverMaxSlashPercentage_WithDelegation(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI101"));

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_Dispute_WithDelegation_DelegationSlashing(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        // enable delegation slashing
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();

        tokensSlash = bound(
            tokensSlash,
            1,
            uint256(maxSlashingPercentage).mulPPM(_calculateStakeSnapshot(tokens, tokensDelegated))
        );

        // Create a new dispute with delegation slashing enabled
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI2"));

        resetPrank(users.arbitrator);
        _acceptDispute(disputeID, tokensSlash);
    }

    function test_Indexing_Accept_RevertWhen_SlashingOverMaxSlashPercentage_WithDelegation_DelegationSlashing(
        uint256 tokens,
        uint256 tokensDelegated,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) useDelegation(tokensDelegated) {
        // enable delegation slashing
        resetPrank(users.governor);
        staking.setDelegationSlashingEnabled();

        uint256 maxTokensToSlash = uint256(maxSlashingPercentage).mulPPM(
            _calculateStakeSnapshot(tokens, tokensDelegated)
        );
        tokensSlash = bound(tokensSlash, maxTokensToSlash + 1, type(uint256).max);

        // Create a new dispute with delegation slashing enabled
        resetPrank(users.fisherman);
        bytes32 disputeID = _createIndexingDispute(allocationID, bytes32("POI101"));

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeID, tokensSlash);
    }
}
