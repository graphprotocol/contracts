// SPDX-License-Identifier: GPL-2.0-or-later

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

pragma solidity ^0.7.6;
pragma abicoder v2;

import { IL1GraphTokenLockTransferTool } from "@graphprotocol/interfaces/contracts/contracts/staking/IL1GraphTokenLockTransferTool.sol";

/**
 * @title L1StakingV1Storage
 * @author Edge & Node
 * @notice This contract holds all the L1-specific storage variables for the L1Staking contract, version 1
 * @dev When adding new versions, make sure to move the gap to the new version and
 * reduce the size of the gap accordingly.
 */
abstract contract L1StakingV1Storage {
    /// @notice If an indexer has transferred to L2, this mapping will hold the indexer's address in L2
    mapping(address => address) public indexerTransferredToL2;
    /// @dev For locked indexers/delegations, this contract holds the mapping of L1 to L2 addresses
    IL1GraphTokenLockTransferTool internal l1GraphTokenLockTransferTool;
    /// @dev Storage gap to keep storage slots fixed in future versions
    uint256[50] private __gap;
}
