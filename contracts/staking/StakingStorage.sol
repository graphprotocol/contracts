// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

import { IStakingData } from "./IStakingData.sol";
import { Stakes } from "./libs/Stakes.sol";

/**
 * @title StakingV1Storage
 * @notice This contract holds all the storage variables for the Staking contract, version 1
 * @dev Note that we use a double underscore prefix for variable names; this prefix identifies
 * variables that used to be public but are now internal, getters can be found on StakingExtension.sol.
 */
// solhint-disable-next-line max-states-count
contract StakingV1Storage is Managed {
    // -- Staking --

    /// @dev Minimum amount of tokens an indexer needs to stake
    uint256 internal __minimumIndexerStake;

    /// @dev Time in blocks to unstake
    uint32 internal __thawingPeriod; // in blocks

    /// @dev Percentage of fees going to curators
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 internal __curationPercentage;

    /// @dev Percentage of fees burned as protocol fee
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 internal __protocolPercentage;

    /// @dev Period for allocation to be finalized
    uint32 private __DEPRECATED_channelDisputeEpochs; // solhint-disable-line var-name-mixedcase

    /// @dev Maximum allocation time
    uint32 internal __maxAllocationEpochs;

    /// @dev Rebate alpha numerator
    // Originally used for Cobb-Douglas rebates, now used for exponential rebates
    uint32 internal __alphaNumerator;

    /// @dev Rebate alpha denominator
    // Originally used for Cobb-Douglas rebates, now used for exponential rebates
    uint32 internal __alphaDenominator;

    /// @dev Indexer stakes : indexer => Stake
    mapping(address => Stakes.Indexer) internal __stakes;

    /// @dev Allocations : allocationID => Allocation
    mapping(address => IStakingData.Allocation) internal __allocations;

    /// @dev Subgraph Allocations: subgraphDeploymentID => tokens
    mapping(bytes32 => uint256) internal __subgraphAllocations;

    // Rebate pools : epoch => Pool
    mapping(uint256 => uint256) private __DEPRECATED_rebates; // solhint-disable-line var-name-mixedcase

    // -- Slashing --

    /// @dev List of addresses allowed to slash stakes
    mapping(address => bool) internal __slashers;

    // -- Delegation --

    /// @dev Set the delegation capacity multiplier defined by the delegation ratio
    /// If delegation ratio is 100, and an Indexer has staked 5 GRT,
    /// then they can use up to 500 GRT from the delegated stake
    uint32 internal __delegationRatio;

    /// @dev Time in blocks an indexer needs to wait to change delegation parameters (deprecated)
    uint32 internal __DEPRECATED_delegationParametersCooldown; // solhint-disable-line var-name-mixedcase

    /// @dev Time in epochs a delegator needs to wait to withdraw delegated stake
    uint32 internal __delegationUnbondingPeriod; // in epochs

    /// @dev Percentage of tokens to tax a delegation deposit
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 internal __delegationTaxPercentage;

    /// @dev Delegation pools : indexer => DelegationPool
    mapping(address => IStakingData.DelegationPool) internal __delegationPools;

    // -- Operators --

    /// @dev Operator auth : indexer => operator => is authorized
    mapping(address => mapping(address => bool)) internal __operatorAuth;

    // -- Asset Holders --

    /// @dev DEPRECATED: Allowed AssetHolders: assetHolder => is allowed
    mapping(address => bool) private __DEPRECATED_assetHolders; // solhint-disable-line var-name-mixedcase
}

/**
 * @title StakingV2Storage
 * @notice This contract holds all the storage variables for the Staking contract, version 2
 * @dev Note that we use a double underscore prefix for variable names; this prefix identifies
 * variables that used to be public but are now internal, getters can be found on StakingExtension.sol.
 */
contract StakingV2Storage is StakingV1Storage {
    /// @dev Destination of accrued rewards : beneficiary => rewards destination
    mapping(address => address) internal __rewardsDestination;
}

/**
 * @title StakingV3Storage
 * @notice This contract holds all the storage variables for the base Staking contract, version 3.
 */
contract StakingV3Storage is StakingV2Storage {
    /// @dev Address of the counterpart Staking contract on L1/L2
    address internal counterpartStakingAddress;
    /// @dev Address of the StakingExtension implementation
    address internal extensionImpl;
}

/**
 * @title StakingV4Storage
 * @notice This contract holds all the storage variables for the base Staking contract, version 4.
 * @dev Note that it includes a storage gap - if adding future versions, make sure to move the gap
 * to the new version and reduce the size of the gap accordingly.
 */
contract StakingV4Storage is StakingV3Storage {
    // Additional rebate parameters for exponential rebates
    uint32 internal __lambdaNumerator;
    uint32 internal __lambdaDenominator;

    /// @dev Gap to allow adding variables in future upgrades (since L1Staking and L2Staking can have their own storage as well)
    uint256[50] private __gap;
}
