// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../discovery/GNS.sol";

/**
 * @title LegacyGNSMock contract
 */
contract LegacyGNSMock is GNS {
    function createLegacySubgraph(uint256 subgraphNumber, bytes32 subgraphDeploymentID) external {
        SubgraphData storage subgraphData = legacySubgraphData[msg.sender][subgraphNumber];
        legacySubgraphs[msg.sender][subgraphNumber] = subgraphDeploymentID;
        subgraphData.subgraphDeploymentID = subgraphDeploymentID;
        subgraphData.nSignal = 1000; // Mock value
    }

    function getSubgraphDeploymentID(uint256 subgraphID)
        external
        view
        returns (bytes32 subgraphDeploymentID)
    {
        IGNS.SubgraphData storage subgraph = _getSubgraphData(subgraphID);
        subgraphDeploymentID = subgraph.subgraphDeploymentID;
    }

    function getSubgraphNSignal(uint256 subgraphID) external view returns (uint256 nSignal) {
        IGNS.SubgraphData storage subgraph = _getSubgraphData(subgraphID);
        nSignal = subgraph.nSignal;
    }
}
