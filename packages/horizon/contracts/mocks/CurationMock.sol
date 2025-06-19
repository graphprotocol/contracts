// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

contract CurationMock {
    mapping(bytes32 subgraphDeploymentID => uint256 tokens) public curation;

    function signal(bytes32 subgraphDeploymentID, uint256 tokens) public {
        curation[subgraphDeploymentID] += tokens;
    }

    function isCurated(bytes32 subgraphDeploymentID) public view returns (bool) {
        return curation[subgraphDeploymentID] != 0;
    }

    function collect(bytes32 subgraphDeploymentID, uint256 tokens) external {
        curation[subgraphDeploymentID] += tokens;
    }
}
