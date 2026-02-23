// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// Needed for abi and typechain in the npm package
/**
 * @title ENS Registry Interface
 * @author Edge & Node
 * @notice Interface for the Ethereum Name Service registry
 */
interface IENS {
    /**
     * @notice Get the owner of a node
     * @param node The node to query
     * @return The address of the owner
     */
    function owner(bytes32 node) external view returns (address);

    /**
     * @notice Set the record for a subnode
     * @dev Must call setRecord, not setOwner. We must namehash it ourselves as well.
     * @param node The parent node
     * @param label The label hash of the subnode
     * @param _owner The address of the new owner
     * @param resolver The address of the resolver
     * @param ttl The TTL in seconds
     */
    function setSubnodeRecord(bytes32 node, bytes32 label, address _owner, address resolver, uint64 ttl) external;
}
