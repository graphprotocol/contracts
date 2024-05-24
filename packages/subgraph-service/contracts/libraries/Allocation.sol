// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

library Allocation {
    using Allocation for State;

    struct State {
        address indexer;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
        uint256 createdAt;
        uint256 closedAt;
        uint256 lastPOIPresentedAt;
        uint256 accRewardsPerAllocatedToken;
        uint256 accRewardsPending;
    }

    error AllocationAlreadyExists(address allocationId);
    error AllocationDoesNotExist(address allocationId);
    error AllocationClosed(address allocationId, uint256 closedAt);
    error AllocationZeroTokens(address allocationId);

    function create(
        mapping(address => State) storage self,
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken
    ) internal returns (State memory) {
        if (self[allocationId].exists()) revert AllocationAlreadyExists(allocationId);

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

    // Update POI timestamp and take rewards snapshot
    // For stale POIs this ensures the rewards are not collected with the next valid POI
    function presentPOI(mapping(address => State) storage self, address allocationId) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        if (!allocation.isOpen()) revert AllocationClosed(allocationId, allocation.closedAt);
        if (allocation.isAltruistic()) revert AllocationZeroTokens(allocationId);
        allocation.lastPOIPresentedAt = block.timestamp;

        return allocation;
    }

    function snapshotRewards(
        mapping(address => State) storage self,
        address allocationId,
        uint256 accRewardsPerAllocatedToken
    ) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        if (!allocation.isOpen()) revert AllocationClosed(allocationId, allocation.closedAt);
        allocation.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;

        return allocation;
    }

    function clearPendingRewards(
        mapping(address => State) storage self,
        address allocationId
    ) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        if (!allocation.isOpen()) revert AllocationClosed(allocationId, allocation.closedAt);
        allocation.accRewardsPending = 0;

        return allocation;
    }

    function close(mapping(address => State) storage self, address allocationId) internal returns (State memory) {
        State storage allocation = _get(self, allocationId);
        if (!allocation.isOpen()) revert AllocationClosed(allocationId, allocation.closedAt);
        allocation.closedAt = block.timestamp;

        return allocation;
    }

    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

    function exists(State memory self) internal pure returns (bool) {
        return self.createdAt != 0;
    }

    function isOpen(State memory self) internal pure returns (bool) {
        return self.exists() && self.closedAt == 0;
    }

    function isAltruistic(State memory self) internal pure returns (bool) {
        return self.exists() && self.tokens == 0;
    }

    function _get(mapping(address => State) storage self, address allocationId) private view returns (State storage) {
        State storage allocation = self[allocationId];
        if (!allocation.exists()) revert AllocationDoesNotExist(allocationId);
        return allocation;
    }
}
