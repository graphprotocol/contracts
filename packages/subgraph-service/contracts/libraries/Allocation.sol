// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Allocation library
 * @notice A library to handle Allocations.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library Allocation {
    using Allocation for State;

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
     * @param createdAtEpoch The epoch when the allocation was created
     * @return The allocation
     */
    function create(
        mapping(address => State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken,
        uint256 createdAtEpoch
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
            accRewardsPending: 0,
            createdAtEpoch: createdAtEpoch
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
    function presentPOI(mapping(address => State) storage self, address allocationId) internal {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.lastPOIPresentedAt = block.timestamp;
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
    ) internal {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
    }

    /**
     * @notice Update the accumulated rewards pending to be claimed for an allocation
     * @dev Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function clearPendingRewards(mapping(address => State) storage self, address allocationId) internal {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.accRewardsPending = 0;
    }

    /**
     * @notice Close an allocation
     * @dev Requirements:
     * - The allocation must be open
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     */
    function close(mapping(address => State) storage self, address allocationId) internal {
        State storage allocation = _get(self, allocationId);
        require(allocation.isOpen(), AllocationClosed(allocationId, allocation.closedAt));
        allocation.closedAt = block.timestamp;
    }

    /**
     * @notice Get an allocation
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     * @return The allocation
     */
    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    /**
     * @notice Checks if an allocation is stale
     * @param self The allocation
     * @param staleThreshold The time in blocks to consider an allocation stale
     * @return True if the allocation is stale
     */
    function isStale(State memory self, uint256 staleThreshold) internal view returns (bool) {
        uint256 timeSinceLastPOI = block.timestamp - Math.max(self.createdAt, self.lastPOIPresentedAt);
        return self.isOpen() && timeSinceLastPOI > staleThreshold;
    }

    /**
     * @notice Checks if an allocation exists
     * @param self The allocation
     * @return True if the allocation exists
     */
    function exists(State memory self) internal pure returns (bool) {
        return self.createdAt != 0;
    }

    /**
     * @notice Checks if an allocation is open
     * @param self The allocation
     * @return True if the allocation is open
     */
    function isOpen(State memory self) internal pure returns (bool) {
        return self.exists() && self.closedAt == 0;
    }

    /**
     * @notice Checks if an allocation is alturistic
     * @param self The allocation
     * @return True if the allocation is alturistic
     */
    function isAltruistic(State memory self) internal pure returns (bool) {
        return self.exists() && self.tokens == 0;
    }

    /**
     * @notice Get the allocation for an allocation id
     * @dev Reverts if the allocation does not exist
     * @param self The allocation list mapping
     * @param allocationId The allocation id
     * @return The allocation
     */
    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        require(allocation.exists(), AllocationDoesNotExist(allocationId));
        return allocation;
    }
}
