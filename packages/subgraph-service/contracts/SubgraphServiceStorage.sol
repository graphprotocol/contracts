// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IDisputeManager } from "./IDisputeManager.sol";
import { ISubgraphService } from "./ISubgraphService.sol";

contract SubgraphServiceV1Storage {
    /// @notice The Horizon staking contract
    IHorizonStaking public immutable staking;

    /// @notice The dispute manager contract
    IDisputeManager public disputeManager;

    /// @notice The minimum amount of tokens required to register a provision in the data service
    uint256 public minimumProvisionTokens;

    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;
}
