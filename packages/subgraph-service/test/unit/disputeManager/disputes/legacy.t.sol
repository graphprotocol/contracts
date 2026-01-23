// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "@graphprotocol/interfaces/contracts/subgraph-service/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerLegacyDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    bytes32 private requestCid = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCid = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_LegacyDispute(
        uint256 tokensStaked,
        uint256 tokensProvisioned,
        uint256 tokensSlash,
        uint256 tokensRewards
    ) public {
        vm.assume(tokensStaked <= MAX_TOKENS);
        vm.assume(tokensStaked >= MINIMUM_PROVISION_TOKENS);
        tokensProvisioned = bound(tokensProvisioned, MINIMUM_PROVISION_TOKENS, tokensStaked);
        tokensSlash = bound(tokensSlash, 2, tokensProvisioned);
        tokensRewards = bound(tokensRewards, 1, tokensSlash.mulPPM(FISHERMAN_REWARD_PERCENTAGE));

        // setup indexer state
        resetPrank(users.indexer);
        _stake(tokensStaked);
        _setStorageAllocationHardcoded(users.indexer, allocationId, tokensStaked - tokensProvisioned);
        _provision(users.indexer, tokensProvisioned, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);

        resetPrank(users.arbitrator);
        _createAndAcceptLegacyDispute(allocationId, users.fisherman, tokensSlash, tokensRewards);
    }

    function test_LegacyDispute_RevertIf_NotArbitrator() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.createAndAcceptLegacyDispute(allocationId, users.fisherman, 0, 0);
    }

    function test_LegacyDispute_RevertIf_AllocationNotFound() public useIndexer {
        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerIndexerNotFound.selector, address(0)));
        disputeManager.createAndAcceptLegacyDispute(address(0), users.fisherman, 0, 0);
    }
}
