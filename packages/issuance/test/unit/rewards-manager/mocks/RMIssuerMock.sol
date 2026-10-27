// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsIssuer } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";

/// Rewards issuer (subgraph service) stand-in for RewardsManager.
contract RMIssuerMock is IRewardsIssuer {
    struct Allocation {
        bool isActive;
        address indexer;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
        uint256 accRewardsPerAllocatedToken;
        uint256 accRewardsPending;
    }

    IRewardsManager public rm;

    mapping(address allocationId => Allocation allocation) private _allocations;
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) private _subgraphAllocatedTokens;

    function setRewardsManager(address rm_) external {
        rm = IRewardsManager(rm_);
    }

    /// Hook first, so the snapshot is taken before the allocated tokens change.
    function allocate(address allocationId, address indexer, bytes32 sd, uint256 tokens) external {
        uint256 snapshot = rm.onSubgraphAllocationUpdate(sd);
        _allocations[allocationId] = Allocation(true, indexer, sd, tokens, snapshot, 0);
        _subgraphAllocatedTokens[sd] += tokens;
    }

    /// Takes rewards while the allocation is still active, then deactivates it.
    /// @dev Legacy Staking called `onSubgraphAllocationUpdate` instead of `takeRewards` for a zero POI or an
    /// allocation under one epoch old. Only the zero-reward cases in `legacySuite.t.sol` hit that case, and they call
    /// the hook themselves.
    function close(address allocationId) external returns (uint256 rewards) {
        rewards = rm.takeRewards(allocationId);
        Allocation storage allocation = _allocations[allocationId];
        allocation.isActive = false;
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] -= allocation.tokens;
    }

    function setAllocation(
        address allocationId,
        bool isActive,
        address indexer,
        bytes32 sd,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken,
        uint256 accRewardsPending
    ) external {
        _allocations[allocationId] = Allocation(
            isActive,
            indexer,
            sd,
            tokens,
            accRewardsPerAllocatedToken,
            accRewardsPending
        );
    }

    function setSubgraphAllocatedTokens(bytes32 sd, uint256 tokens) external {
        _subgraphAllocatedTokens[sd] = tokens;
    }

    function reclaim(bytes32 reason, address allocationId) external returns (uint256) {
        return rm.reclaimRewards(reason, allocationId);
    }

    function getAllocationData(
        address allocationId
    )
        external
        view
        override
        returns (
            bool isActive,
            address indexer,
            bytes32 subgraphDeploymentId,
            uint256 tokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        )
    {
        Allocation storage allocation = _allocations[allocationId];
        return (
            allocation.isActive,
            allocation.indexer,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            allocation.accRewardsPerAllocatedToken,
            allocation.accRewardsPending
        );
    }

    function getSubgraphAllocatedTokens(bytes32 sd) external view override returns (uint256) {
        return _subgraphAllocatedTokens[sd];
    }
}
