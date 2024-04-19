// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

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
    }

    error AllocationAlreadyExists(address allocationId);
    error AllocationAlreadyClosed(address allocationId, uint256 closedAt);
    error AllocationDoesNotExist(address allocationId);

    function get(mapping(address => State) storage self, address allocationId) internal view returns (State memory) {
        return _get(self, allocationId);
    }

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
            lastPOIPresentedAt: block.timestamp,
            accRewardsPerAllocatedToken: accRewardsPerAllocatedToken
        });

        self[allocationId] = allocation;

        return allocation;
    }

    function presentPOI(
        mapping(address => State) storage self,
        address allocationId,
        uint256 accRewardsPerAllocatedToken
    ) internal {
        State storage allocation = _get(self, allocationId);
        allocation.lastPOIPresentedAt = block.timestamp;
        allocation.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
    }

    function close(
        mapping(address => State) storage self,
        address allocationId,
        uint256 accRewardsPerAllocatedToken
    ) internal {
        State storage allocation = _get(self, allocationId);
        if (!allocation.isOpen()) revert AllocationAlreadyClosed(allocationId, allocation.closedAt);
        allocation.closedAt = block.timestamp;
        allocation.accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
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
