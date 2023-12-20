// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { ICallhookReceiver } from "../../gateway/ICallhookReceiver.sol";

/**
 * @title Interface for the L2GNS contract.
 */
interface IL2GNS is ICallhookReceiver {
    enum L1MessageCodes {
        RECEIVE_SUBGRAPH_CODE,
        RECEIVE_CURATOR_BALANCE_CODE
    }

    /**
     * @dev The SubgraphL2TransferData struct holds information
     * about a subgraph related to its transfer from L1 to L2.
     */
    struct SubgraphL2TransferData {
        uint256 tokens; // GRT that will be sent to L2 to mint signal
        mapping(address => bool) curatorBalanceClaimed; // True for curators whose balance has been claimed in L2
        bool l2Done; // Transfer finished on L2 side
        uint256 subgraphReceivedOnL2BlockNumber; // Block number when the subgraph was received on L2
    }

    /**
     * @notice Finish a subgraph transfer from L1.
     * The subgraph must have been previously sent through the bridge
     * using the sendSubgraphToL2 function on L1GNS.
     * @param _l2SubgraphID Subgraph ID in L2 (aliased from the L1 subgraph ID)
     * @param _subgraphDeploymentID Latest subgraph deployment to assign to the subgraph
     * @param _subgraphMetadata IPFS hash of the subgraph metadata
     * @param _versionMetadata IPFS hash of the version metadata
     */
    function finishSubgraphTransferFromL1(
        uint256 _l2SubgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _subgraphMetadata,
        bytes32 _versionMetadata
    ) external;

    /**
     * @notice Return the aliased L2 subgraph ID from a transferred L1 subgraph ID
     * @param _l1SubgraphID L1 subgraph ID
     * @return L2 subgraph ID
     */
    function getAliasedL2SubgraphID(uint256 _l1SubgraphID) external pure returns (uint256);

    /**
     * @notice Return the unaliased L1 subgraph ID from a transferred L2 subgraph ID
     * @param _l2SubgraphID L2 subgraph ID
     * @return L1subgraph ID
     */
    function getUnaliasedL1SubgraphID(uint256 _l2SubgraphID) external pure returns (uint256);
}
