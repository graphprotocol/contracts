// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

/**
 * @title SubgraphServiceStorage
 * @author Edge & Node
 * @notice This contract holds all the storage variables for the Subgraph Service contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract SubgraphServiceV1Storage is ISubgraphService {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public override indexers;

    ///@notice Multiplier for how many tokens back collected query fees
    uint256 public override stakeToFeesRatio;

    /// @notice The cut curators take from query fee payments. In PPM.
    uint256 public override curationFeesCut;

    /// @notice Destination of indexer payments
    mapping(address indexer => address destination) public override paymentsDestination;
}
