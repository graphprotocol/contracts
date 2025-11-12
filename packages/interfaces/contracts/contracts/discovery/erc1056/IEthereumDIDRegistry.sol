// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Ethereum DID Registry Interface
 * @author Edge & Node
 * @notice Interface for the Ethereum DID Registry contract
 */
interface IEthereumDIDRegistry {
    /**
     * @notice Get the owner of an identity
     * @param identity The identity address
     * @return The address of the identity owner
     */
    function identityOwner(address identity) external view returns (address);

    /**
     * @notice Set an attribute for an identity
     * @param identity The identity address
     * @param name The attribute name
     * @param value The attribute value
     * @param validity The validity period in seconds
     */
    function setAttribute(address identity, bytes32 name, bytes calldata value, uint256 validity) external;
}
