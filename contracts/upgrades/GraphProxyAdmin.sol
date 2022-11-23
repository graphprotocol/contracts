// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Governed } from "../governance/Governed.sol";

import { IGraphProxy } from "./IGraphProxy.sol";
import { GraphUpgradeable } from "./GraphUpgradeable.sol";

/**
 * @title GraphProxyAdmin
 * @dev This is the owner of upgradeable proxy contracts.
 * Proxy contracts use a TransparentProxy pattern, any admin related call
 * like upgrading a contract or changing the admin needs to be send through
 * this contract.
 */
contract GraphProxyAdmin is Governed {
    /**
     * @notice Contract constructor.
     */
    constructor() {
        Governed._initialize(msg.sender);
    }

    /**
     * @notice Returns the current implementation of a proxy.
     * @dev This is needed because only the proxy admin can query it.
     * @param _proxy Address of the proxy for which to get the implementation.
     * @return The address of the current implementation of the proxy.
     */
    function getProxyImplementation(IGraphProxy _proxy) external view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = address(_proxy).staticcall(hex"5c60da1b");
        require(success, "Proxy impl call failed");
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Returns the pending implementation of a proxy.
     * @dev This is needed because only the proxy admin can query it.
     * @param _proxy Address of the proxy for which to get the pending implementation.
     * @return The address of the pending implementation of the proxy.
     */
    function getProxyPendingImplementation(IGraphProxy _proxy) external view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("pendingImplementation()")) == 0x396f7b23
        (bool success, bytes memory returndata) = address(_proxy).staticcall(hex"396f7b23");
        require(success, "Proxy pendingImpl call failed");
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Returns the admin of a proxy. Only the admin can query it.
     * @param _proxy Address of the proxy for which to get the admin.
     * @return The address of the current admin of the proxy.
     */
    function getProxyAdmin(IGraphProxy _proxy) external view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = address(_proxy).staticcall(hex"f851a440");
        require(success, "Proxy admin call failed");
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Changes the admin of a proxy.
     * @param _proxy Proxy to change admin.
     * @param _newAdmin Address to transfer proxy administration to.
     */
    function changeProxyAdmin(IGraphProxy _proxy, address _newAdmin) external onlyGovernor {
        _proxy.setAdmin(_newAdmin);
    }

    /**
     * @notice Upgrades a proxy to the newest implementation of a contract.
     * @param _proxy Proxy to be upgraded.
     * @param _implementation the address of the Implementation.
     */
    function upgrade(IGraphProxy _proxy, address _implementation) external onlyGovernor {
        _proxy.upgradeTo(_implementation);
    }

    /**
     * @notice Accepts a proxy.
     * @param _implementation Address of the implementation accepting the proxy.
     * @param _proxy Address of the proxy being accepted.
     */
    function acceptProxy(GraphUpgradeable _implementation, IGraphProxy _proxy)
        external
        onlyGovernor
    {
        _implementation.acceptProxy(_proxy);
    }

    /**
     * @notice Accepts a proxy and call a function on the implementation.
     * @param _implementation Address of the implementation accepting the proxy.
     * @param _proxy Address of the proxy being accepted.
     * @param _data Encoded function to call on the implementation after accepting the proxy.
     */
    function acceptProxyAndCall(
        GraphUpgradeable _implementation,
        IGraphProxy _proxy,
        bytes calldata _data
    ) external onlyGovernor {
        _implementation.acceptProxyAndCall(_proxy, _data);
    }
}
