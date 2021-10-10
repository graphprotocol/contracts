// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../governance/Managed.sol";

import "./IStakingData.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

contract StakingV1Storage is Managed {
    // -- Staking --

    // Minimum amount of tokens an indexer needs to stake
    uint256 public minimumIndexerStake;

    // Time in blocks to unstake
    uint32 public thawingPeriod; // in blocks

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public curationPercentage;

    // Percentage of fees burned as protocol fee
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public protocolPercentage;

    // Period for allocation to be finalized
    uint32 public channelDisputeEpochs;

    // Maximum allocation time
    uint32 public maxAllocationEpochs;

    // Rebate ratio
    uint32 public alphaNumerator;
    uint32 public alphaDenominator;

    // Indexer stakes : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    // Allocations : allocationID => Allocation
    mapping(address => IStakingData.Allocation) public allocations;

    // Subgraph Allocations: subgraphDeploymentID => tokens
    mapping(bytes32 => uint256) public subgraphAllocations;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // -- Slashing --

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // -- Delegation --

    // Set the delegation capacity multiplier defined by the delegation ratio
    // If delegation ratio is 100, and an Indexer has staked 5 GRT,
    // then they can use up to 500 GRT from the delegated stake
    uint32 public delegationRatio;

    // Time in blocks an indexer needs to wait to change delegation parameters
    uint32 public delegationParametersCooldown;

    // Time in epochs a delegator needs to wait to withdraw delegated stake
    uint32 public delegationUnbondingPeriod; // in epochs

    // Percentage of tokens to tax a delegation deposit
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public delegationTaxPercentage;

    // Delegation pools : indexer => DelegationPool
    mapping(address => IStakingData.DelegationPool) public delegationPools;

    // -- Operators --

    // Operator auth : indexer => operator
    mapping(address => mapping(address => bool)) public operatorAuth;

    // -- Asset Holders --

    // Allowed AssetHolders: assetHolder => is allowed
    mapping(address => bool) public assetHolders;
}

contract StakingV2Storage is StakingV1Storage {
    // Destination of accrued rewards : beneficiary => rewards destination
    mapping(address => address) public rewardsDestination;
}
