// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

contract SubgraphServiceV1Storage {
    // Graph protocol contracts
    /// @notice The Horizon staking contract
    IHorizonStaking public immutable staking;
    IGraphEscrow public immutable escrow;
    IGraphPayments public immutable payments;

    // Data service contracts
    /// @notice The dispute manager contract
    IDisputeManager public disputeManager;

    /// @notice The TAP verifier contract
    ITAPVerifier public tapVerifier;

    /// @notice The minimum amount of tokens required to register a provision in the data service
    uint256 public minimumProvisionTokens;

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
