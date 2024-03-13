// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { L1GNS } from "../discovery/L1GNS.sol";
import { IGNS } from "../discovery/IGNS.sol";

/**
 * @title LegacyGNSMock contract
 * @dev This is used to test the migration of legacy subgraphs to NFT-based subgraphs and transferring them to L2
 */
contract LegacyGNSMock is L1GNS {
    /**
     * @notice Create a mock legacy subgraph (owned by the msg.sender)
     * @param subgraphNumber Number of the subgraph (sequence ID for the account)
     * @param subgraphDeploymentID Subgraph deployment ID
     */
    function createLegacySubgraph(uint256 subgraphNumber, bytes32 subgraphDeploymentID) external {
        SubgraphData storage subgraphData = legacySubgraphData[msg.sender][subgraphNumber];
        legacySubgraphs[msg.sender][subgraphNumber] = subgraphDeploymentID;
        subgraphData.subgraphDeploymentID = subgraphDeploymentID;
        subgraphData.nSignal = 1000; // Mock value
    }

    /**
     * @notice Get the subgraph deployment ID for a subgraph
     * @param subgraphID Subgraph ID
     * @return subgraphDeploymentID Subgraph deployment ID
     */
    function getSubgraphDeploymentID(uint256 subgraphID) external view returns (bytes32 subgraphDeploymentID) {
        IGNS.SubgraphData storage subgraph = _getSubgraphData(subgraphID);
        subgraphDeploymentID = subgraph.subgraphDeploymentID;
    }

    /**
     * @notice Get the nSignal for a subgraph
     * @param subgraphID Subgraph ID
     * @return nSignal The subgraph's nSignal
     */
    function getSubgraphNSignal(uint256 subgraphID) external view returns (uint256 nSignal) {
        IGNS.SubgraphData storage subgraph = _getSubgraphData(subgraphID);
        nSignal = subgraph.nSignal;
    }
}
