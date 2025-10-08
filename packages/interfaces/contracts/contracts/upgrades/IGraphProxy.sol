// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title Graph Proxy Interface
 * @author Edge & Node
 * @notice Interface for the Graph Proxy contract that handles upgradeable proxy functionality
 */
interface IGraphProxy {
    /**
     * @notice Get the current admin.
     *
     * @dev NOTE: Only the admin can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     *
     * @return adminAddress The address of the current admin
     */
    function admin() external returns (address);

    /**
     * @notice Change the admin of the proxy.
     *
     * @dev NOTE: Only the admin can call this function.
     *
     * @param newAdmin Address of the new admin
     */
    function setAdmin(address newAdmin) external;

    /**
     * @notice Get the current implementation.
     *
     * @dev NOTE: Only the admin can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
     *
     * @return implementationAddress The address of the current implementation for this proxy
     */
    function implementation() external returns (address);

    /**
     * @notice Get the current pending implementation.
     *
     * @dev NOTE: Only the admin can call this function.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using the
     * https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0x9e5eddc59e0b171f57125ab86bee043d9128098c3a6b9adb4f2e86333c2f6f8c`
     *
     * @return pendingImplementationAddress The address of the current pending implementation for this proxy
     */
    function pendingImplementation() external returns (address);

    /**
     * @notice Upgrades to a new implementation contract.
     * @dev NOTE: Only the admin can call this function.
     * @param newImplementation Address of implementation contract
     */
    function upgradeTo(address newImplementation) external;

    /**
     * @notice Admin function for new implementation to accept its role as implementation.
     */
    function acceptUpgrade() external;

    /**
     * @notice Admin function for new implementation to accept its role as implementation,
     * calling a function on the new implementation.
     * @param data Calldata (including selector) for the function to delegatecall into the implementation
     */
    function acceptUpgradeAndCall(bytes calldata data) external;
}
