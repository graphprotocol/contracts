// SPDX-License-Identifier: GPL-2.0-or-later

// solhint-disable named-parameters-mapping

pragma solidity 0.7.6;

import { IRewardsIssuer } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsIssuer.sol";

/**
 * @title MockSubgraphService
 * @author Edge & Node
 * @notice A mock contract for testing SubgraphService as a rewards issuer
 * @dev Implements IRewardsIssuer interface to simulate SubgraphService behavior in tests
 */
contract MockSubgraphService is IRewardsIssuer {
    /// @dev Struct to store allocation data
    struct Allocation {
        bool isActive;
        address indexer;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
        uint256 accRewardsPerAllocatedToken;
        uint256 accRewardsPending;
    }

    /// @dev Mapping of allocation ID to allocation data
    mapping(address => Allocation) private allocations;

    /// @dev Mapping of subgraph deployment ID to total allocated tokens
    mapping(bytes32 => uint256) private subgraphAllocatedTokens;

    /**
     * @notice Set allocation data for testing
     * @param allocationId The allocation ID
     * @param isActive Whether the allocation is active
     * @param indexer The indexer address
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param tokens Amount of allocated tokens
     * @param accRewardsPerAllocatedToken Rewards snapshot
     * @param accRewardsPending Accumulated rewards pending
     */
    function setAllocation(
        address allocationId,
        bool isActive,
        address indexer,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        uint256 accRewardsPerAllocatedToken,
        uint256 accRewardsPending
    ) external {
        allocations[allocationId] = Allocation({
            isActive: isActive,
            indexer: indexer,
            subgraphDeploymentId: subgraphDeploymentId,
            tokens: tokens,
            accRewardsPerAllocatedToken: accRewardsPerAllocatedToken,
            accRewardsPending: accRewardsPending
        });
    }

    /**
     * @notice Set total allocated tokens for a subgraph
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param tokens Total tokens allocated
     */
    function setSubgraphAllocatedTokens(bytes32 subgraphDeploymentId, uint256 tokens) external {
        subgraphAllocatedTokens[subgraphDeploymentId] = tokens;
    }

    /**
     * @inheritdoc IRewardsIssuer
     */
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
        Allocation memory allocation = allocations[allocationId];
        return (
            allocation.isActive,
            allocation.indexer,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            allocation.accRewardsPerAllocatedToken,
            allocation.accRewardsPending
        );
    }

    /**
     * @inheritdoc IRewardsIssuer
     */
    function getSubgraphAllocatedTokens(bytes32 subgraphDeploymentId) external view override returns (uint256) {
        return subgraphAllocatedTokens[subgraphDeploymentId];
    }
}
