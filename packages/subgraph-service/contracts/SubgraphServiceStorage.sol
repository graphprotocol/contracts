// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

abstract contract SubgraphServiceV1Storage {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;

    // -- Fees --
    // multiplier for how many tokens back collected query fees
    uint256 public stakeToFeesRatio;

    /// @notice The fees cut taken by the subgraph service
    mapping(IGraphPayments.PaymentTypes paymentType => ISubgraphService.PaymentFee paymentFees) public paymentFees;

    mapping(address indexer => mapping(address payer => uint256 tokens)) public tokensCollected;
}
