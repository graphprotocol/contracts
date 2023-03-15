// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { IController } from "./IController.sol";

/**
 * @title Managed Interface
 * @dev Interface for contracts that can be managed by a controller.
 */
interface IManaged {
    /**
     * @notice Set the controller that manages this contract
     * @dev Only the current controller can set a new controller
     * @param _controller Address of the new controller
     */
    function setController(address _controller) external;

    /**
     * @notice Sync protocol contract addresses from the Controller registry
     * @dev This function will cache all the contracts using the latest addresses.
     * Anyone can call the function whenever a Proxy contract change in the
     * controller to ensure the protocol is using the latest version.
     */
    function syncAllContracts() external;

    /**
     * @notice Get the Controller that manages this contract
     * @return The Controller as an IController interface
     */
    function controller() external view returns (IController);
}
