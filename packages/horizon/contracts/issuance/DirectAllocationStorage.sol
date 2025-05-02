// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import "../staking/utilities/Managed.sol";

/**
 * @title DirectAllocationStorage
 * @notice Storage contract for DirectAllocation
 * @dev This contract defines the storage layout for the DirectAllocation contract
 */
abstract contract DirectAllocationStorage is Managed {
    // -- State --

    // Name of this allocation for identification
    string public name;

    // Address that can withdraw funds
    address public manager;
}
