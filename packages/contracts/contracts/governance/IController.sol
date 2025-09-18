// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title Controller Interface
 * @author Edge & Node
 * @notice Interface for the Controller contract that manages protocol governance and contract registry
 */
interface IController {
    /**
     * @notice Return the governor address
     * @return The governor address
     */
    function getGovernor() external view returns (address);

    // -- Registry --

    /**
     * @notice Register contract id and mapped address
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _contractAddress Contract address
     */
    function setContractProxy(bytes32 _id, address _contractAddress) external;

    /**
     * @notice Unregister a contract address
     * @param _id Contract id (keccak256 hash of contract name)
     */
    function unsetContractProxy(bytes32 _id) external;

    /**
     * @notice Update contract's controller
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _controller Controller address
     */
    function updateController(bytes32 _id, address _controller) external;

    /**
     * @notice Get contract proxy address by its id
     * @param _id Contract id
     * @return Address of the proxy contract for the provided id
     */
    function getContractProxy(bytes32 _id) external view returns (address);

    // -- Pausing --

    /**
     * @notice Change the partial paused state of the contract
     * Partial pause is intended as a partial pause of the protocol
     * @param _partialPaused True if the contracts should be (partially) paused, false otherwise
     */
    function setPartialPaused(bool _partialPaused) external;

    /**
     * @notice Change the paused state of the contract
     * Full pause most of protocol functions
     * @param _paused True if the contracts should be paused, false otherwise
     */
    function setPaused(bool _paused) external;

    /**
     * @notice Change the Pause Guardian
     * @param _newPauseGuardian The address of the new Pause Guardian
     */
    function setPauseGuardian(address _newPauseGuardian) external;

    /**
     * @notice Return whether the protocol is paused
     * @return True if the protocol is paused
     */
    function paused() external view returns (bool);

    /**
     * @notice Return whether the protocol is partially paused
     * @return True if the protocol is partially paused
     */
    function partialPaused() external view returns (bool);
}
