// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import "../staking/utilities/Managed.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import "./DirectAllocationStorage.sol";

/**
 * @title DirectAllocation
 * @notice A simple contract that receives tokens from the IssuanceAllocator and allows
 * an authorized manager to withdraw them. This contract can be used for both Pilot Allocation
 * and Innovation Allocation, with different configurations.
 *
 * @dev This contract is designed to be a non-self-minting target in the IssuanceAllocator.
 * The IssuanceAllocator will mint tokens directly to this contract, and the authorized
 * manager can withdraw them as needed.
 */
contract DirectAllocation is Initializable, GraphUpgradeable, DirectAllocationStorage {
    // -- Custom Errors --

    error OnlyManagerCanSendTokens();
    error SendToZeroAddressNotAllowed();
    error OnlyImplementationCanInitialize();
    error ControllerMismatch();

    /**
     * @notice Constructor for the DirectAllocation contract
     * @dev This contract is upgradeable, but we use the constructor to disable initializers
     * to prevent the implementation contract from being initialized.
     * @dev We need to pass a valid controller address to the Managed constructor because
     * GraphDirectory requires a non-zero controller address. This controller will only be
     * used for the implementation contract, not for the proxy.
     * @param _controller Controller contract that manages this contract
     */
    constructor(address _controller) Managed(_controller) {
        _disableInitializers();
    }

    // -- Events --

    event ManagerSet(address indexed oldManager, address indexed newManager);
    event TokensSent(address indexed to, uint256 amount);

    // -- Initialization --

    /**
     * @notice Initialize the DirectAllocation contract
     * @param _controller Controller contract that manages this contract
     * @param _name Name of this allocation for identification
     * @param _manager Address that can withdraw funds
     */
    function initialize(address _controller, string calldata _name, address _manager) external onlyImpl initializer {
        if (_controller != address(_graphController())) revert ControllerMismatch();

        name = _name;
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
