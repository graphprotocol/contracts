// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import { Governed } from "@graphprotocol/contracts/contracts/governance/Governed.sol";
import { GraphDirectory } from "../utilities/GraphDirectory.sol";
import { DirectAllocationStorage } from "./DirectAllocationStorage.sol";

/**
 * @title DirectAllocation
 * @notice A simple contract that receives tokens from the IssuanceAllocator and allows
 * an authorized manager to withdraw them. This contract can be used for both Pilot Allocation
 * and Innovation Allocation, with different configurations.
 *
 * @dev This contract is designed to be a non-self-minting target in the IssuanceAllocator.
 * The IssuanceAllocator will mint tokens directly to this contract, and the authorized
 * manager can send them to individual addresses as needed.
 */
contract DirectAllocation is Initializable, GraphUpgradeable, Governed, GraphDirectory, DirectAllocationStorage {
    // -- Custom Errors --

    error OnlyImplementationCanInitialize();
    error ControllerCannotBeZeroAddress();
    error OnlyManagerCanSendTokens();
    error SendToZeroAddressNotAllowed();

    // -- Events --

    event ManagerSet(address indexed oldManager, address indexed newManager);
    event TokensSent(address indexed to, uint256 amount);

    /**
     * @notice Constructor for the DirectAllocation contract
     * @dev This contract is upgradeable, but we use the constructor to disable initializers
     * to prevent the implementation contract from being initialized.
     * @param _controller Controller contract that manages this contract
     */
    constructor(address _controller) GraphDirectory(_controller) {
        _disableInitializers();
    }

    // -- Initialization --

    /**
     * @notice Initialize the DirectAllocation contract
     * @param _controller Controller contract that manages this contract
     * @param _manager Address that can withdraw funds
     */
    function initialize(address _controller, address _manager) external initializer {
        if (msg.sender != _implementation()) revert OnlyImplementationCanInitialize();
        if (_controller == address(0)) revert ControllerCannotBeZeroAddress();

        Governed._initialize(_graphController().getGovernor());
        manager = _manager;
    }

    // -- External Functions --

    /**
     * @notice Set the manager address
     * @dev This function can only be called by the governor
     * @dev If the new manager is the same as the current manager, this function is a no-op
     * @param _manager New manager address
     */
    function setManager(address _manager) external onlyGovernor {
        // Allow zero address as manager if needed
        if (_manager == manager) return; // No-op if same value

        address oldManager = manager;
        manager = _manager;

        emit ManagerSet(oldManager, _manager);
    }

    /**
     * @notice Send tokens to a specified address
     * @dev This function can only be called by the manager
     * @param _to Address to send tokens to
     * @param _amount Amount of tokens to send
     */
    function sendTokens(address _to, uint256 _amount) external {
        if (msg.sender != manager) revert OnlyManagerCanSendTokens();
        if (_to == address(0)) revert SendToZeroAddressNotAllowed(); // Zero address likely to be a mistake

        _graphToken().transfer(_to, _amount);
        emit TokensSent(_to, _amount);
    }

    /**
     * @notice Get the current balance of GRT tokens in this contract
     * @return Current balance of GRT tokens
     */
    function getBalance() external view returns (uint256) {
        return _graphToken().balanceOf(address(this));
    }
}
