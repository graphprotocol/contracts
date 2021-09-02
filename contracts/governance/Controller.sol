// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "./IController.sol";
import "./IManaged.sol";
import "./Governed.sol";
import "./Pausable.sol";

/**
 * @title Graph Controller contract
 * @dev Controller is a registry of contracts for convenience. Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Controller is Governed, Pausable, IController {
    // Track contract ids to contract proxy address
    mapping(bytes32 => address) private registry;

    event SetContractProxy(bytes32 indexed id, address contractAddress);

    /** 
     * @dev Contract constructor.
     */
    constructor() {
        Governed._initialize(msg.sender);

        _setPaused(true);
    }

    /**
     * @dev Check if the caller is the governor or pause guardian.
     */
    modifier onlyGovernorOrGuardian {
        require(
            msg.sender == governor || msg.sender == pauseGuardian,
            "Only Governor or Guardian can call"
        );
        _;
    }

    /**
     * @notice Getter to access governor
     */
    function getGovernor() external override view returns (address) {
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
        registry[_id] = _contractAddress;
        emit SetContractProxy(_id, _contractAddress);
    }

    /**
     * @notice Unregister a contract address
     * @param _id Contract id (keccak256 hash of contract name)
     */
    function unsetContractProxy(bytes32 _id)
        external
        override
        onlyGovernor
    {
        registry[_id] = address(0);
        emit SetContractProxy(_id, address(0));
    }

    /**
     * @notice Get contract proxy address by its id
     * @param _id Contract id
     */
    function getContractProxy(bytes32 _id) public override view returns (address) {
        return registry[_id];
    }

    /**
     * @notice Update contract's controller
     * @param _id Contract id (keccak256 hash of contract name)
     * @param _controller Controller address
     */
    function updateController(bytes32 _id, address _controller) external override onlyGovernor {
        require(_controller != address(0), "Controller must be set");
        return IManaged(registry[_id]).setController(_controller);
    }

    // -- Pausing --

    /**
     * @notice Change the partial paused state of the contract
     * Partial pause is intended as a partial pause of the protocol
     */
    function setPartialPaused(bool _partialPaused) external override onlyGovernorOrGuardian {
        _setPartialPaused(_partialPaused);
    }

    /**
     * @notice Change the paused state of the contract
     * Full pause most of protocol functions
     */
    function setPaused(bool _paused) external override onlyGovernorOrGuardian {
        _setPaused(_paused);
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
     */
    function paused() external override view returns (bool) {
        return _paused;
    }

    /**
     * @notice Getter to access partial pause status
     */
    function partialPaused() external override view returns (bool) {
        return _partialPaused;
    }
}
