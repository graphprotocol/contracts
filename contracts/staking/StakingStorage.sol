pragma solidity ^0.6.4;

import "../EpochManager.sol";
import "../curation/ICuration.sol";
import "../staking/IStaking.sol";
import "../token/IGraphToken.sol";
import "../upgrades/GraphProxyStorage.sol";

import "./IStaking.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

contract StakingV1Storage is GraphProxyStorage {
    // -- Staking --

    // Time in blocks to unstake
    uint256 public thawingPeriod; // in blocks

    // Indexer stake tracking : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public curationPercentage;

    // Percentage of fees burned as protocol fee
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public protocolPercentage;

    // Need to pass this period for channel to be finalized
    uint256 public channelDisputeEpochs;

    // Maximum allocation time
    uint256 public maxAllocationEpochs;

    // Allocations : allocationID => Allocation
    mapping(address => IStaking.Allocation) public allocations;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // -- Slashing --

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // Set the delegation capacity multiplier.
    // If delegation capacity is 100 GRT, and an Indexer has staked 5 GRT,
    // then they can accept 500 GRT as delegated stake.
    uint256 public delegationCapacity;

    // Time in blocks an indexer needs to wait to change delegation parameters
    uint256 public delegationParametersCooldown;

    // Delegation pools : indexer => DelegationPool
    mapping(address => IStaking.DelegationPool) public delegation;

    // -- Related contracts --

    IGraphToken public token;
    EpochManager public epochManager;
    ICuration public curation;
}
