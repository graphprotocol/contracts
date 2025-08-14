// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events, gas-small-strings

/* solhint-disable gas-custom-errors */ // Cannot use custom errors with 0.7.6

import { IController } from "./IController.sol";
import { IManaged } from "./IManaged.sol";
import { Governed } from "./Governed.sol";
import { Pausable } from "./Pausable.sol";

/**
 * @title Graph Controller contract
 * @author Edge & Node
 * @notice Controller is a registry of contracts for convenience. Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Controller is Governed, Pausable, IController {
    /// @dev Track contract ids to contract proxy address
    mapping(bytes32 => address) private _registry;

    /**
     * @notice Emitted when the proxy address for a protocol contract has been set
     * @param id Contract identifier
     * @param contractAddress Address of the contract proxy
     */
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
        require(msg.sender == governor || msg.sender == pauseGuardian, "Only Governor or Guardian can call");
        _;
    }

    /**
     * @inheritdoc IController
     */
    function getGovernor() external view override returns (address) {
        return governor;
    }

    // -- Registry --

    /**
     * @inheritdoc IController
     */
    function setContractProxy(bytes32 _id, address _contractAddress) external override onlyGovernor {
        require(_contractAddress != address(0), "Contract address must be set");
        _registry[_id] = _contractAddress;
        emit SetContractProxy(_id, _contractAddress);
    }

    /**
     * @inheritdoc IController
     */
    function unsetContractProxy(bytes32 _id) external override onlyGovernor {
        _registry[_id] = address(0);
        emit SetContractProxy(_id, address(0));
    }

    /**
     * @inheritdoc IController
     */
    function getContractProxy(bytes32 _id) external view override returns (address) {
        return _registry[_id];
    }

    /**
     * @inheritdoc IController
     */
    function updateController(bytes32 _id, address _controller) external override onlyGovernor {
        require(_controller != address(0), "Controller must be set");
        return IManaged(_registry[_id]).setController(_controller);
    }

    // -- Pausing --

    /**
     * @inheritdoc IController
     * @dev Partial pause is intended as a partial pause of the protocol
     */
    function setPartialPaused(bool _toPause) external override onlyGovernorOrGuardian {
        _setPartialPaused(_toPause);
    }

    /**
     * @inheritdoc IController
     * @dev Full pause most of protocol functions
     */
    function setPaused(bool _toPause) external override onlyGovernorOrGuardian {
        _setPaused(_toPause);
    }

    /**
     * @inheritdoc IController
     */
    function setPauseGuardian(address _newPauseGuardian) external override onlyGovernor {
        require(_newPauseGuardian != address(0), "PauseGuardian must be set");
        _setPauseGuardian(_newPauseGuardian);
    }

    /**
     * @inheritdoc IController
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @inheritdoc IController
     */
    function partialPaused() external view override returns (bool) {
        return _partialPaused;
    }
}
