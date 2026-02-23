// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

/**
 * @title CurationMock
 * @author Edge & Node
 * @notice Mock implementation of curation functionality for testing
 */
contract CurationMock {
    /// @notice Mapping of subgraph deployment ID to curation tokens
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) public curation;

    /**
     * @notice Signal curation tokens for a subgraph deployment
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param tokens The amount of tokens to signal
     */
    function signal(bytes32 subgraphDeploymentId, uint256 tokens) public {
        curation[subgraphDeploymentId] += tokens;
    }

    /**
     * @notice Check if a subgraph deployment is curated
     * @param subgraphDeploymentId The subgraph deployment ID
     * @return True if the subgraph deployment has curation tokens
     */
    function isCurated(bytes32 subgraphDeploymentId) public view returns (bool) {
        return curation[subgraphDeploymentId] != 0;
    }

    /**
     * @notice Collect curation tokens for a subgraph deployment
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param tokens The amount of tokens to collect
     */
    function collect(bytes32 subgraphDeploymentId, uint256 tokens) external {
        curation[subgraphDeploymentId] += tokens;
    }
}
