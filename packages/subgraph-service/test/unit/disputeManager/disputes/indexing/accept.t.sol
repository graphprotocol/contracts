// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerIndexingAcceptDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    /*
     * TESTS
     */

    function test_Indexing_Accept_Dispute(uint256 tokens, uint256 tokensSlash) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, tokensSlash);
    }

    function test_Indexing_Accept_Dispute_RevertWhen_SubgraphServiceNotSet(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        // clear subgraph service address from storage
        _setStorageSubgraphService(address(0));

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerSubgraphServiceNotSet.selector));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Indexing_Accept_Dispute_OptParam(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        resetPrank(users.arbitrator);
        _acceptDispute(disputeId, tokensSlash);
    }

    function test_Indexing_Accept_RevertIf_CallerIsNotArbitrator(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        tokensSlash = bound(tokensSlash, 1, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens));

        resetPrank(users.fisherman);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI1"), block.number);

        // attempt to accept dispute as fisherman
        resetPrank(users.fisherman);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }

    function test_Indexing_Accept_RevertWhen_SlashingOverMaxSlashPercentage(
        uint256 tokens,
        uint256 tokensSlash
    ) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        tokensSlash = bound(tokensSlash, uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens) + 1, type(uint256).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 disputeId = _createIndexingDispute(allocationId, bytes32("POI101"), block.number);

        // max slashing percentage is 50%
        resetPrank(users.arbitrator);
        uint256 maxTokensToSlash = uint256(MAX_SLASHING_PERCENTAGE).mulPPM(tokens);
        bytes memory expectedError = abi.encodeWithSelector(
            IDisputeManager.DisputeManagerInvalidTokensSlash.selector,
            tokensSlash,
            maxTokensToSlash
        );
        vm.expectRevert(expectedError);
        disputeManager.acceptDispute(disputeId, tokensSlash);
    }
}
