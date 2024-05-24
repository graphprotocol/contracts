// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { GraphDirectory } from "../../data-service/GraphDirectory.sol";

// TODO: create custom var-name-mixedcase
/* solhint-disable var-name-mixedcase */

/**
 * @title Graph Managed contract
 * @dev The Managed contract provides an interface to interact with the Controller.
 * Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
abstract contract Managed is GraphDirectory {
    // -- State --

    /// Controller that manages this contract
    address private __DEPRECATED_controller;
    /// @dev Cache for the addresses of the contracts retrieved from the controller
    mapping(bytes32 contractName => address contractAddress) private __DEPRECATED_addressCache;
    /// @dev Gap for future storage variables
    uint256[10] private __gap;

    error ManagedIsPaused();
    error ManagedOnlyController();
    error ManagedOnlyGovernor();

    /**
     * @dev Revert if the controller is paused
     */
    modifier notPaused() {
        require(!_graphController().paused(), ManagedIsPaused());
        _;
    }

    /**
     * @dev Revert if the caller is not the Controller
     */
    modifier onlyController() {
        require(msg.sender == address(_graphController()), ManagedOnlyController());
        _;
    }

    /**
     * @dev Revert if the caller is not the governor
     */
    modifier onlyGovernor() {
        require(msg.sender == _graphController().getGovernor(), ManagedOnlyGovernor());
        _;
    }

    constructor(address controller_) GraphDirectory(controller_) {}
}
