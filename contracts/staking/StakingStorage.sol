pragma solidity ^0.6.4;

import "../governance/Manager.sol";
import "../staking/IStaking.sol";
import "./IStaking.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

contract StakingV1Storage is Manager {
    // -- Staking --

    // Time in blocks to unstake
    uint32 public thawingPeriod; // in blocks

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public curationPercentage;

    // Percentage of fees burned as protocol fee
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public protocolPercentage;

    // Need to pass this period for channel to be finalized
    uint32 public channelDisputeEpochs;

    // Maximum allocation time
    uint32 public maxAllocationEpochs;

    // Indexer stakes : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    // Allocations : allocationID => Allocation
    mapping(address => IStaking.Allocation) public allocations;

    // Subgraph Allocations: subgraphDeploymentID => tokens
    mapping(bytes32 => uint256) public subgraphAllocations;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // -- Slashing --

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // -- Delegation --

    // Set the delegation capacity multiplier
    // If delegation capacity is 100 GRT, and an Indexer has staked 5 GRT,
    // then they can accept 500 GRT as delegated stake
    uint32 public delegationCapacity;

    // Time in blocks an indexer needs to wait to change delegation parameters
    uint32 public delegationParametersCooldown;

    // Time in epochs a delegator needs to wait to withdraw delegated stake
    uint32 public delegationUnbondingPeriod; // in epochs

    // Delegation pools : indexer => DelegationPool
    mapping(address => IStaking.DelegationPool) public delegationPools;

    // -- Operators --

    // Operator auth : indexer => operator
    mapping(address => mapping(address => bool)) public operatorAuth;
}
