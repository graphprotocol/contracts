// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Attestation } from "../../../contracts/libraries/Attestation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { IDisputeManager } from "../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../DisputeManager.t.sol";

contract DisputeManagerLegacyDisputeTest is DisputeManagerTest {
    using PPMMath for uint256;

    bytes32 private requestHash = keccak256(abi.encodePacked("Request hash"));
    bytes32 private responseHash = keccak256(abi.encodePacked("Response hash"));
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
        vm.assume(tokensStaked >= minimumProvisionTokens);
        tokensProvisioned = bound(tokensProvisioned, minimumProvisionTokens, tokensStaked);
        tokensSlash = bound(tokensSlash, 2, tokensProvisioned);
        tokensRewards = bound(tokensRewards, 1, tokensSlash.mulPPM(fishermanRewardPercentage));

        // setup indexer state
        resetPrank(users.indexer);
        _stake(tokensStaked);
        _setStorage_allocation_hardcoded(users.indexer, allocationID, tokensStaked - tokensProvisioned);
        _provision(users.indexer, tokensProvisioned, fishermanRewardPercentage, disputePeriod);

        resetPrank(users.arbitrator);
        _createAndAcceptLegacyDispute(allocationID, users.fisherman, tokensSlash, tokensRewards);
    }

    function test_LegacyDispute_RevertIf_NotArbitrator() public useIndexer {
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotArbitrator.selector));
        disputeManager.createAndAcceptLegacyDispute(allocationID, users.fisherman, 0, 0);
    }

    function test_LegacyDispute_RevertIf_AllocationNotFound() public useIndexer {
        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerIndexerNotFound.selector, address(0)));
        disputeManager.createAndAcceptLegacyDispute(address(0), users.fisherman, 0, 0);
    }
}
