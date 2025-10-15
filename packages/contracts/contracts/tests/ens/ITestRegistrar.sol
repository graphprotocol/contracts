// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @title Test Registrar Interface
 * @author Edge & Node
 * @notice Interface for a test ENS registrar contract
 */
interface ITestRegistrar {
    /**
     * @notice Register a name with the registrar
     * @param label The label hash to register
     * @param owner The address to assign ownership to
     */
    function register(bytes32 label, address owner) external;
}
