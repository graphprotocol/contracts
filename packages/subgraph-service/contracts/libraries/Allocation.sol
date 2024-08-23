// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Allocation library
 * @notice A library to handle Allocations.
 */
library Allocation {
    using Allocation for State;

    /**
     * @notice Allocation details
     */
    struct State {
        // Indexer that owns the allocation
        address indexer;
        // Subgraph deployment id the allocation is for
        bytes32 subgraphDeploymentId;
        // Number of tokens allocated
        uint256 tokens;
        // Timestamp when the allocation was created
        uint256 createdAt;
        // Timestamp when the allocation was closed
        uint256 closedAt;
        // Timestamp when the last POI was presented
        uint256 lastPOIPresentedAt;
        // Accumulated rewards per allocated token
        uint256 accRewardsPerAllocatedToken;
        // Accumulated rewards that are pending to be claimed due allocation resize
        uint256 accRewardsPending;
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

    /**
     * @notice Create a new allocation
     * @dev Requirements:
     * - The allocation must not exist
     * @param self The allocation list mapping
     * @param indexer The indexer that owns the allocation
     * @param allocationId The allocation id
     * @param subgraphDeploymentId The subgraph deployment id the allocation is for
     * @param tokens The number of tokens allocated
     * @param accRewardsPerAllocatedToken The initial accumulated rewards per allocated token
     */
    function create(
        mapping(address => State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken
    ) internal returns (State memory) {
        require(!self[allocationId].exists(), AllocationAlreadyExists(allocationId));

        State memory allocation = State({
            indexer: indexer,
            subgraphDeploymentId: subgraphDeploymentId,
            tokens: tokens,
            createdAt: block.timestamp,
            closedAt: 0,
            lastPOIPresentedAt: 0,
            accRewardsPerAllocatedToken: accRewardsPerAllocatedToken,
            accRewardsPending: 0
        });

        self[allocationId] = allocation;

        return allocation;
    }

    /**
     * @notice Present a POI for an allocation
     * @dev It only updates the last POI presented timestamp.
     * Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function presentPOI(mapping(address => State) storage self, address allocationId) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.lastPOIPresentedAt = block.timestamp;

        return allocation;
    }

    /**
     * @notice Update the accumulated rewards per allocated token for an allocation
     * @dev Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     * @param accRewardsPerAllocatedToken The new accumulated rewards per allocated token
     */
    function snapshotRewards(
        mapping(address => State) storage self,
        address allocationId,
        uint256 accRewardsPerAllocatedToken
    ) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;

        return allocation;
    }

    /**
     * @notice Update the accumulated rewards pending to be claimed for an allocation
     * @dev Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function clearPendingRewards(
        mapping(address => State) storage self,
        address allocationId
    ) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.accRewardsPending = 0;

        return allocation;
    }

    /**
     * @notice Close an allocation
     * @dev Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function close(mapping(address => State) storage self, address allocationId) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.closedAt = block.timestamp;

        return allocation;
    }

    /**
     * @notice Get an allocation
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    /**
     * @notice Checks if an allocation is stale
     * @param self The allocation
     * @param staleThreshold The time in blocks to consider an allocation stale
     */
    function isStale(State memory self, uint256 staleThreshold) internal view returns (bool) {
        uint256 timeSinceLastPOI = block.timestamp - Math.max(self.createdAt, self.lastPOIPresentedAt);
        return self.isOpen() && timeSinceLastPOI > staleThreshold;
    }

    /**
     * @notice Checks if an allocation exists
     * @param self The allocation
     */
    function exists(State memory self) internal pure returns (bool) {
        return self.createdAt != 0;
    }

    /**
     * @notice Checks if an allocation is open
     * @param self The allocation
     */
    function isOpen(State memory self) internal pure returns (bool) {
        return self.exists() && self.closedAt == 0;
    }

    /**
     * @notice Checks if an allocation is closed
     * @param self The allocation
     */
    function isAltruistic(State memory self) internal pure returns (bool) {
        return self.exists() && self.tokens == 0;
    }

    /**
     * @notice Get the allocation for an allocation id
     * @dev Reverts if the allocation does not exist
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        require(allocation.exists(), AllocationDoesNotExist(allocationId));
        return allocation;
    }
}
