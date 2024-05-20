// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IManaged } from "@graphprotocol/contracts/contracts/governance/IManaged.sol";

/**
 * @title Graph Controller contract (mock)
 * @dev Controller is a registry of contracts for convenience. Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract ControllerMock is IController {
    /// @dev Track contract ids to contract proxy address
    mapping(bytes32 contractName => address contractAddress) private _registry;
    address public governor;
    bool internal _paused;
    bool internal _partialPaused;
    address internal _pauseGuardian;

    /// Emitted when the proxy address for a protocol contract has been set
    event SetContractProxy(bytes32 indexed id, address contractAddress);

    /**
     * Constructor for the Controller mock
     * @param governor_ Address of the governor
     */
    constructor(address governor_) {
        governor = governor_;
    }

    // -- Registry --

    /**
     * @notice Register contract id and mapped address
     * @param id Contract id (keccak256 hash of contract name)
     * @param contractAddress Contract address
     */
    function setContractProxy(bytes32 id, address contractAddress) external override {
        require(contractAddress != address(0), "Contract address must be set");
        _registry[id] = contractAddress;
        emit SetContractProxy(id, contractAddress);
    }

    /**
     * @notice Unregister a contract address
     * @param id Contract id (keccak256 hash of contract name)
     */
    function unsetContractProxy(bytes32 id) external override {
        _registry[id] = address(0);
        emit SetContractProxy(id, address(0));
    }

    /**
     * @notice Update a contract's controller
     * @param id Contract id (keccak256 hash of contract name)
     * @param controller New Controller address
     */
    function updateController(bytes32 id, address controller) external override {
        require(controller != address(0), "Controller must be set");
        return IManaged(_registry[id]).setController(controller);
    }

    // -- Pausing --

    /**
     * @notice Change the partial paused state of the contract
     * Partial pause is intended as a partial pause of the protocol
     * @param toPause True if the contracts should be (partially) paused, false otherwise
     */
    function setPartialPaused(bool toPause) external override {
        _partialPaused = toPause;
    }

    /**
     * @notice Change the paused state of the contract
     * Full pause most of protocol functions
     * @param toPause True if the contracts should be paused, false otherwise
     */
    function setPaused(bool toPause) external override {
        _paused = toPause;
    }

    /**
     * @notice Change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function setPauseGuardian(address newPauseGuardian) external override {
        require(newPauseGuardian != address(0), "PauseGuardian must be set");
        _pauseGuardian = newPauseGuardian;
    }

    /**
     * @notice Getter to access governor
     * @return Address of the governor
     */
    function getGovernor() external view override returns (address) {
        return governor;
    }

    /**
     * @notice Get contract proxy address by its id
     * @param id Contract id (keccak256 hash of contract name)
     * @return Address of the proxy contract for the provided id
     */
    function getContractProxy(bytes32 id) external view override returns (address) {
        return _registry[id];
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
