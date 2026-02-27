// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { SubgraphServiceTest } from "./SubgraphService.t.sol";

contract SubgraphServiceGettersTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_GetDisputeManager() public view {
        address result = subgraphService.getDisputeManager();
        assertEq(result, address(disputeManager));
    }

    function test_GetGraphTallyCollector() public view {
        address result = subgraphService.getGraphTallyCollector();
        assertEq(result, address(graphTallyCollector));
    }

    function test_GetCuration() public view {
        address result = subgraphService.getCuration();
        assertEq(result, address(curation));
    }

    function test_GetAllocationData(uint256 tokens) public useIndexer useAllocation(tokens) {
        (
            bool isOpen,
            address indexer,
            bytes32 subgraphDeploymentIdResult,
            uint256 allocatedTokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        ) = subgraphService.getAllocationData(allocationId);

        assertTrue(isOpen);
        assertEq(indexer, users.indexer);
        assertEq(subgraphDeploymentIdResult, subgraphDeployment);
        assertEq(allocatedTokens, tokens);
        assertEq(accRewardsPerAllocatedToken, 0);
        assertEq(accRewardsPending, 0);
    }

    function test_GetAllocationData_NonExistent() public view {
        address nonExistent = address(0xdead);
        (
            bool isOpen,
            address indexer,
            bytes32 subgraphDeploymentIdResult,
            uint256 allocatedTokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        ) = subgraphService.getAllocationData(nonExistent);

        assertFalse(isOpen);
        assertEq(indexer, address(0));
        assertEq(subgraphDeploymentIdResult, bytes32(0));
        assertEq(allocatedTokens, 0);
        assertEq(accRewardsPerAllocatedToken, 0);
        assertEq(accRewardsPending, 0);
    }

    function test_GetProvisionTokensRange() public view {
        (uint256 min, uint256 max) = subgraphService.getProvisionTokensRange();
        assertEq(min, MINIMUM_PROVISION_TOKENS);
        assertEq(max, type(uint256).max);
    }

    function test_GetThawingPeriodRange() public view {
        (uint64 min, uint64 max) = subgraphService.getThawingPeriodRange();
        uint64 expectedDisputePeriod = disputeManager.getDisputePeriod();
        assertEq(min, expectedDisputePeriod);
        assertEq(max, expectedDisputePeriod);
    }

    function test_GetVerifierCutRange() public view {
        (uint32 min, uint32 max) = subgraphService.getVerifierCutRange();
        uint32 expectedFishermanRewardCut = disputeManager.getFishermanRewardCut();
        assertEq(min, expectedFishermanRewardCut);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(max, uint32(MAX_PPM));
    }
}
