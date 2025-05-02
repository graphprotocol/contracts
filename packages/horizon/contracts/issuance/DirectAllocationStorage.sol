// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title DirectAllocationStorage
 * @notice Storage contract for DirectAllocation
 * @dev This contract defines the storage layout for the DirectAllocation contract
 */
abstract contract DirectAllocationStorage {
    // -- State --

    // Address that can send tokens
    address public manager;

    // -- Storage Gap --

    // Gap for future storage variables in upgrades
    uint256[50] private __gap;
}
