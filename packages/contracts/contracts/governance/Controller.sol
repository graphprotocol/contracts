// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { IController } from "./IController.sol";
import { IManaged } from "./IManaged.sol";
import { Governed } from "./Governed.sol";
import { Pausable } from "./Pausable.sol";

/**
 * @title Graph Controller contract
 * @dev Controller is a registry of contracts for convenience. Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Controller is Governed, Pausable, IController {
    /// @dev Track contract ids to contract proxy address
    mapping(bytes32 => address) private _registry;

    /// Emitted when the proxy address for a protocol contract has been set
    event SetContractProxy(bytes32 indexed id, address contractAddress);

    /**
     * @notice Controller contract constructor.
     */
    constructor() {
        Governed._initialize(msg.sender);

        _setPaused(true);
    }

    /**
     * @dev Check if the caller is the governor or pause guardian.
     */
    modifier onlyGovernorOrGuardian() {
        require(
            msg.sender == governor || msg.sender == pauseGuardian,
            "Only Governor or Guardian can call"
        );
        _;
    }

    /**
     * @notice Getter to access governor
     */
    function getGovernor() external view override returns (address) {
        return governor;
    }

    // -- Registry --

    /**
     * @notice Register contract id and mapped address
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _contractAddress Contract address
     */
    function setContractProxy(bytes32 _id, address _contractAddress)
        external
        override
        onlyGovernor
    {
        require(_contractAddress != address(0), "Contract address must be set");
        _registry[_id] = _contractAddress;
        emit SetContractProxy(_id, _contractAddress);
    }

    /**
     * @notice Unregister a contract address
     * @param _id Contract id (keccak256 hash of contract name)
     */
    function unsetContractProxy(bytes32 _id) external override onlyGovernor {
        _registry[_id] = address(0);
        emit SetContractProxy(_id, address(0));
    }

    /**
     * @notice Get contract proxy address by its id
     * @param _id Contract id
     * @return Address of the proxy contract for the provided id
     */
    function getContractProxy(bytes32 _id) external view override returns (address) {
        return _registry[_id];
    }

    /**
     * @notice Update contract's controller
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _controller Controller address
     */
    function updateController(bytes32 _id, address _controller) external override onlyGovernor {
        require(_controller != address(0), "Controller must be set");
        return IManaged(_registry[_id]).setController(_controller);
    }

    // -- Pausing --

    /**
     * @notice Change the partial paused state of the contract
     * Partial pause is intended as a partial pause of the protocol
     * @param _toPause True if the contracts should be (partially) paused, false otherwise
     */
    function setPartialPaused(bool _toPause) external override onlyGovernorOrGuardian {
        _setPartialPaused(_toPause);
    }

    /**
     * @notice Change the paused state of the contract
     * Full pause most of protocol functions
     * @param _toPause True if the contracts should be paused, false otherwise
     */
    function setPaused(bool _toPause) external override onlyGovernorOrGuardian {
        _setPaused(_toPause);
    }

    /**
     * @notice Change the Pause Guardian
     * @param _newPauseGuardian The address of the new Pause Guardian
     */
    function setPauseGuardian(address _newPauseGuardian) external override onlyGovernor {
        require(_newPauseGuardian != address(0), "PauseGuardian must be set");
        _setPauseGuardian(_newPauseGuardian);
    }

    /**
     * @notice Getter to access paused
     * @return True if the contracts are paused, false otherwise
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @notice Getter to access partial pause status
     * @return True if the contracts are partially paused, false otherwise
     */
    function partialPaused() external view override returns (bool) {
        return _partialPaused;
    }
}
