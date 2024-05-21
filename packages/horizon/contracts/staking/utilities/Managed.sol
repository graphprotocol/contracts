// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IManaged } from "../../interfaces/IManaged.sol";

import { GraphDirectory } from "../../GraphDirectory.sol";

// TODO: create custom var-name-mixedcase
/* solhint-disable var-name-mixedcase */

/**
 * @title Graph Managed contract
 * @dev The Managed contract provides an interface to interact with the Controller.
 * Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
abstract contract Managed is IManaged, GraphDirectory {
    // -- State --

    /// Controller that manages this contract
    IController private __DEPRECATED_controller;
    /// @dev Cache for the addresses of the contracts retrieved from the controller
    mapping(bytes32 contractName => address contractAddress) private __DEPRECATED_addressCache;
    /// @dev Gap for future storage variables
    uint256[10] private __gap;

    // -- Events --

    /// Emitted when a contract parameter has been updated
    event ParameterUpdated(string param);

    error ManagedSetControllerDeprecated();

    /**
     * @dev Revert if the controller is paused or partially paused
     */
    modifier notPartialPaused() {
        require(!controller().paused(), "Paused");
        require(!controller().partialPaused(), "Partial-paused");
        _;
    }

    /**
     * @dev Revert if the controller is paused
     */
    modifier notPaused() {
        require(!controller().paused(), "Paused");
        _;
    }

    /**
     * @dev Revert if the caller is not the Controller
     */
    modifier onlyController() {
        require(msg.sender == CONTROLLER, "Caller must be Controller");
        _;
    }

    /**
     * @dev Revert if the caller is not the governor
     */
    modifier onlyGovernor() {
        require(msg.sender == controller().getGovernor(), "Only Controller governor");
        _;
    }

    constructor(address controller_) GraphDirectory(controller_) {}

    /**
     * @notice Set Controller. Deprecated, will revert.
     */
    function setController(address) external view override onlyController {
        revert ManagedSetControllerDeprecated();
    }

    function controller() public view override returns (IController) {
        return IController(CONTROLLER);
    }
}
