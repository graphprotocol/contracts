// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import "../upgrades/GraphUpgradeable.sol";
import "../governance/Managed.sol";
import "../token/IGraphToken.sol";
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
contract DirectAllocation is DirectAllocationStorage, GraphUpgradeable, Managed {
    // -- Custom Errors --

    error OnlyManagerCanSendTokens();
    error ZeroAddressNotAllowed();

    // -- Events --

    event ManagerSet(address indexed oldManager, address indexed newManager);
    event TokensSent(address indexed to, uint256 amount);

    // -- Initialization --

    /**
     * @notice Initialize the DirectAllocation contract
     * @param _controller Address of the controller contract
     * @param _name Name of this allocation for identification
     * @param _manager Address that can withdraw funds
     */
    function initialize(address _controller, string calldata _name, address _manager) external onlyImpl {
        Managed._initialize(_controller);

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
        if (_to == address(0)) revert ZeroAddressNotAllowed(); // Zero address doesn't make sense for token transfers

        graphToken().transfer(_to, _amount);
        emit TokensSent(_to, _amount);
    }

    /**
     * @notice Get the current balance of GRT tokens in this contract
     * @return Current balance of GRT tokens
     */
    function getBalance() external view returns (uint256) {
        return graphToken().balanceOf(address(this));
    }
}
