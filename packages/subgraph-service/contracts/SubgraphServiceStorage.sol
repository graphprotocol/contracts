// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable named-parameters-mapping

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

/**
 * @title SubgraphServiceStorage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the Subgraph Service contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract SubgraphServiceV1Storage {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;

    ///@notice Multiplier for how many tokens back collected query fees
    uint256 public stakeToFeesRatio;

    /// @notice The cut curators take from query fee payments. In PPM.
    uint256 public curationFeesCut;

    /// @notice Destination of indexer payments
    mapping(address indexer => address destination) public paymentsDestination;
}
