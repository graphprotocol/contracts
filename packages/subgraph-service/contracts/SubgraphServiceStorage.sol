// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

abstract contract SubgraphServiceV1Storage {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;

    ///@notice Multiplier for how many tokens back collected query fees
    uint256 public stakeToFeesRatio;

    /// @notice The cut curators take from query fee payments
    uint256 public curationFeesCut;
}
