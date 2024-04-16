// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

contract SubgraphServiceV1Storage {
    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;

    // -- Fees --
    // multiplier for how many tokens back collected query fees
    uint256 public stakeToFeesRatio;

    /// @notice The fees cut taken by the subgraph service
    uint256 public feesCut;

    mapping(address indexer => mapping(address payer => uint256 tokens)) public tokensCollected;

    // -- Indexing rewards --

    mapping(address indexer => uint256 tokens) public provisionTrackerAllocations;
    mapping(address allocationId => ISubgraphService.Allocation allocation) public allocations;

    /// @notice Track total tokens allocated per subgraph deployment
    /// @dev Used to calculate indexing rewards
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) public subgraphAllocations;
}
