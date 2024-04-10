// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { ISubgraphDisputeManager } from "./interfaces/ISubgraphDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

contract SubgraphServiceV1Storage {
    // multiplier for how many tokens back collected query fees
    uint256 stakeToFeesRatio;

    /// @notice Service providers registered in the data service
    mapping(address indexer => ISubgraphService.Indexer details) public indexers;

    // tokens collected so far from the scalar escrow
    mapping(address indexer => mapping(address payer => uint256 tokens)) public tokensCollected;

    /// @notice List of locked stake claims to be released to service providers
    mapping(bytes32 claimId => ISubgraphService.StakeClaim claim) public claims;

    mapping(address allocationId => ISubgraphService.Allocation allocation) public allocations;
}
