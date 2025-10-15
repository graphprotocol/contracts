// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// Needed for abi and typechain in the npm package
/**
 * @title ENS Public Resolver Interface
 * @author Edge & Node
 * @notice Interface for the ENS public resolver contract
 */
interface IPublicResolver {
    /**
     * @notice Get the text record for a node
     * @param node The node to query
     * @param key The key of the text record
     * @return The text record value
     */
    function text(bytes32 node, string calldata key) external view returns (string memory);

    /**
     * @notice Set the text record for a node
     * @param node The node to set the record for
     * @param key The key of the text record
     * @param value The value to set
     */
    function setText(bytes32 node, string calldata key, string calldata value) external;
}
