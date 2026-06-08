// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.22;

import { IGraphProxy } from "./IGraphProxy.sol";
import { IGoverned } from "../governance/IGoverned.sol";

/**
 * @title IGraphProxyAdmin
 * @author Edge & Node
 * @notice GraphProxyAdmin contract interface for managing proxy contracts
 * @dev Note that this interface is not used by the contract implementation, just used for types and abi generation
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IGraphProxyAdmin is IGoverned {
    /**
     * @notice Get the implementation address of a proxy
     * @param proxy The proxy contract to query
     * @return The implementation address
     */
    function getProxyImplementation(IGraphProxy proxy) external view returns (address);

    /**
     * @notice Get the pending implementation address of a proxy
     * @param proxy The proxy contract to query
     * @return The pending implementation address
     */
    function getProxyPendingImplementation(IGraphProxy proxy) external view returns (address);

    /**
     * @notice Get the admin address of a proxy
     * @param proxy The proxy contract to query
     * @return The admin address
     */
    function getProxyAdmin(IGraphProxy proxy) external view returns (address);

    /**
     * @notice Change the admin of a proxy contract
     * @param proxy The proxy contract to modify
     * @param newAdmin The new admin address
     */
    function changeProxyAdmin(IGraphProxy proxy, address newAdmin) external;

    /**
     * @notice Upgrade a proxy to a new implementation
     * @param proxy The proxy contract to upgrade
     * @param implementation The new implementation address
     */
    function upgrade(IGraphProxy proxy, address implementation) external;

    /**
     * @notice Upgrade a proxy to a new implementation
     * @param proxy The proxy contract to upgrade
     * @param implementation The new implementation address
     */
    function upgradeTo(IGraphProxy proxy, address implementation) external;

    /**
     * @notice Upgrade a proxy to a new implementation and call a function
     * @param proxy The proxy contract to upgrade
     * @param implementation The new implementation address
     * @param data The calldata to execute on the new implementation
     */
    function upgradeToAndCall(IGraphProxy proxy, address implementation, bytes calldata data) external;

    /**
     * @notice Accept ownership of a proxy contract
     * @param proxy The proxy contract to accept
     */
    function acceptProxy(IGraphProxy proxy) external;

    /**
     * @notice Accept ownership of a proxy contract and call a function
     * @param proxy The proxy contract to accept
     * @param data The calldata to execute after accepting
     */
    function acceptProxyAndCall(IGraphProxy proxy, bytes calldata data) external;

    // storage

    /**
     * @notice Get the governor address
     * @return The address of the governor
     */
    function governor() external view returns (address);
}
