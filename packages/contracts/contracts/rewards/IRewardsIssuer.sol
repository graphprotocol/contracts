// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface IRewardsIssuer {
    /**
     * @dev Get allocation data to calculate rewards issuance
     * 
     * @param allocationId The allocation Id
     * @return isActive Whether the allocation is active or not
     * @return indexer The indexer address
     * @return subgraphDeploymentId Subgraph deployment id for the allocation
     * @return tokens Amount of allocated tokens
     * @return accRewardsPerAllocatedToken Rewards snapshot
     * @return accRewardsPending Snapshot of accumulated rewards from previous allocation resizing, pending to be claimed
     */
    function getAllocationData(
        address allocationId
    )
        external
        view
        returns (
            bool isActive,
            address indexer,
            bytes32 subgraphDeploymentId,
            uint256 tokens,
            uint256 accRewardsPerAllocatedToken,
            uint256 accRewardsPending
        );

    /**
     * @notice Return the total amount of tokens allocated to subgraph.
     * @param _subgraphDeploymentId Deployment Id for the subgraph
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 _subgraphDeploymentId) external view returns (uint256);
}
