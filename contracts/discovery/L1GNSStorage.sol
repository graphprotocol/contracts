// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

/**
 * @title L1GNSV1Storage
 * @notice This contract holds all the L1-specific storage variables for the L1GNS contract, version 1
 * @dev
 */
abstract contract L1GNSV1Storage {
    /// Address of the Arbitrum DelayedInbox
    address public arbitrumInboxAddress;
    /// @dev Storage gap to keep storage slots fixed in future versions
    uint256[50] private __gap;
}
