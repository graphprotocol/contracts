// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.6.12 <0.9.0;

interface IRewardsIssuer {
    /**
     * @dev Get allocation data to calculate rewards issuance
     * @param allocationId The allocation ID
     * @return indexer The indexer address
     * @return subgraphDeploymentID Subgraph deployment id for the allocation
     * @return tokens Amount of allocated tokens
     * @return accRewardsPerAllocatedToken Rewards snapshot
     */
    function getAllocationData(
        address allocationId
    )
        external
        view
        returns (address indexer, bytes32 subgraphDeploymentID, uint256 tokens, uint256 accRewardsPerAllocatedToken);
}
