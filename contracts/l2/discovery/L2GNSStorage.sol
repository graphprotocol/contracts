// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../../discovery/IGNS.sol";

/**
 * @dev Storage variables for the L2GNS
 */
contract L2GNSV1Storage {
    // Subgraph data incoming from L1
    mapping(uint256 => IGNS.MigratedSubgraphData) public migratedSubgraphData;
}
