// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { IIssuanceTarget } from "@graphprotocol/contracts/contracts/allocate/IIssuanceTarget.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { Roles } from "../common/Roles.sol";

/**
 * @title DirectAllocation
 * @notice A simple contract that receives tokens from the IssuanceAllocator and allows
 * an authorized operator to withdraw them. This contract can be used for both Pilot Allocation
 * and Innovation Allocation, with different configurations.
 *
 * @dev This contract is designed to be a non-self-minting target in the IssuanceAllocator.
 * The IssuanceAllocator will mint tokens directly to this contract, and the authorized
 * operator can send them to individual addresses as needed.
 */
contract DirectAllocation is BaseUpgradeable, IIssuanceTarget {

    // -- Events --

    /// @notice Emitted when tokens are sent
    event TokensSent(address indexed to, uint256 amount);

    /**
     * @notice Constructor for the DirectAllocation contract
     * @dev This contract is upgradeable, but we use the constructor to pass the Graph Token address
     * to the base contract.
     * @param _graphToken Address of the Graph Token contract
     */
    constructor(address _graphToken) BaseUpgradeable(_graphToken) {}

    /**
     * @notice Send tokens to a specified address
     * @dev This function can only be called by accounts with the OPERATOR_ROLE
     * @param _to Address to send tokens to
     * @param _amount Amount of tokens to send
     */
    function sendTokens(address _to, uint256 _amount) external onlyRole(Roles.OPERATOR) whenNotPaused {
        GRAPH_TOKEN.transfer(_to, _amount);
        emit TokensSent(_to, _amount);
    }

    /**
     * @notice Called by the IssuanceAllocator before the target's issuance allocation changes
     * @dev This function ensures that all issuance related calculations are up-to-date
     * with the current block so that an allocation change can be applied correctly.
     *
     * For DirectAllocation, this is a no-op since we don't need to perform any calculations
     * before an allocation change. We simply receive tokens from the IssuanceAllocator.
     */
    function preIssuanceAllocationChange() external virtual override {
        // No-op for DirectAllocation
        // This contract doesn't need to perform any calculations before an allocation change
    }

    /**
     * @notice Sets the issuance allocator for this target
     * @dev This function facilitates upgrades by providing a standard way for targets
     * to change their allocator. Only the governor can call this function.
     * @param _issuanceAllocator Address of the issuance allocator
     */
    function setIssuanceAllocator(address _issuanceAllocator) external virtual override onlyRole(Roles.GOVERNOR) {
        // No-op for DirectAllocation
        // This contract doesn't need to store the issuance allocator
    }
}
