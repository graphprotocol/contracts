// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

/**
 * @title L1GNSV1Storage
 * @notice This contract holds all the L1-specific storage variables for the L1GNS contract, version 1
 * @dev When adding new versions, make sure to move the gap to the new version and
 * reduce the size of the gap accordingly.
 */
abstract contract L1GNSV1Storage {
    /// True for subgraph IDs that have been transferred to L2
    mapping(uint256 => bool) public subgraphTransferredToL2;
    /// @dev Storage gap to keep storage slots fixed in future versions
    uint256[50] private __gap;
}
