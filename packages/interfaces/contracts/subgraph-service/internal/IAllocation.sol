// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title Interface for the {Allocation} library contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAllocation {
    /**
     * @notice Allocation details
     * @param indexer The indexer that owns the allocation
     * @param subgraphDeploymentId The subgraph deployment id the allocation is for
     * @param tokens The number of tokens allocated
     * @param createdAt The timestamp when the allocation was created
     * @param closedAt The timestamp when the allocation was closed
     * @param lastPOIPresentedAt The timestamp when the last POI was presented
     * @param accRewardsPerAllocatedToken The accumulated rewards per allocated token
     * @param accRewardsPending The accumulated rewards that are pending to be claimed due allocation resize
     * @param createdAtEpoch The epoch when the allocation was created
     */
    struct State {
        address indexer;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
        uint256 createdAt;
        uint256 closedAt;
        uint256 lastPOIPresentedAt;
        uint256 accRewardsPerAllocatedToken;
        uint256 accRewardsPending;
        uint256 createdAtEpoch;
    }

    /**
     * @notice Thrown when attempting to create an allocation with an existing id
     * @param allocationId The allocation id
     */
    error AllocationAlreadyExists(address allocationId);

    /**
     * @notice Thrown when trying to perform an operation on a non-existent allocation
     * @param allocationId The allocation id
     */
    error AllocationDoesNotExist(address allocationId);

    /**
     * @notice Thrown when trying to perform an operation on a closed allocation
     * @param allocationId The allocation id
     * @param closedAt The timestamp when the allocation was closed
     */
    error AllocationClosed(address allocationId, uint256 closedAt);
}
