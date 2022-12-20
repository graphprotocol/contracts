// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { IL2GNS } from "./IL2GNS.sol";

/**
 * @title L2GNSV1Storage
 * @notice This contract holds all the L2-specific storage variables for the L2GNS contract, version 1
 * @dev
 */
abstract contract L2GNSV1Storage {
    /// Data for subgraph migration from L1 to L2
    mapping(uint256 => IL2GNS.SubgraphL2MigrationData) public subgraphL2MigrationData;
    /// @dev Storage gap to keep storage slots fixed in future versions
    uint256[50] private __gap;
}
