// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { GraphDirectory } from "../../utilities/GraphDirectory.sol";

/* solhint-disable var-name-mixedcase */

/**
 * @title Graph Managed contract
 * @dev The Managed contract provides an interface to interact with the Controller.
 * For Graph Horizon this contract is mostly a shell that uses {GraphDirectory}, however since the {HorizonStaking}
 * contract uses it we need to preserve the storage layout.
 * Inspired by Livepeer: https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract Managed is GraphDirectory {
    // -- State --

    /// @notice Controller that manages this contract
    address private __DEPRECATED_controller;

    /// @dev Cache for the addresses of the contracts retrieved from the controller
    mapping(bytes32 contractName => address contractAddress) private __DEPRECATED_addressCache;

    /// @dev Gap for future storage variables
    uint256[10] private __gap;

    /**
     * @notice Thrown when a protected function is called and the contract is paused.
     */
    error ManagedIsPaused();

    /**
     * @notice Thrown when a the caller is not the expected controller address.
     */
    error ManagedOnlyController();

    /**
     * @notice Thrown when a the caller is not the governor.
     */
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

    /**
     * @dev Initialize the contract
     * @param controller_ The address of the Graph controller contract.
     */
    constructor(address controller_) GraphDirectory(controller_) {}
}
