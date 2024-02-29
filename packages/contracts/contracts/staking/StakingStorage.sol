// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { Managed } from "../governance/Managed.sol";

import { IStakingData } from "./IStakingData.sol";
import { Stakes } from "./libs/Stakes.sol";
import { IHorizonStakingTypes } from "../l2/staking/IHorizonStakingTypes.sol";

/**
 * @title StakingV1Storage
 * @notice This contract holds all the storage variables for the Staking contract, version 1
 * @dev Note that we use a double underscore prefix for variable names; this prefix identifies
 * variables that used to be public but are now internal, getters can be found on StakingExtension.sol.
 */
// solhint-disable-next-line max-states-count
contract StakingV1Storage is Managed, IHorizonStakingTypes {
    // -- Staking --

    /// @dev Minimum amount of tokens an indexer needs to stake.
    /// Deprecated, now enforced by each data service (verifier)
    uint256 internal __DEPRECATED_minimumIndexerStake;

    /// @dev Time in blocks to unstake
    /// Deprecated, now enforced by each data service (verifier)
    uint32 internal __DEPRECATED_thawingPeriod; // in blocks

    /// @dev Percentage of fees going to curators
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    /// Deprecated, now enforced by each data service (verifier)
    uint32 internal __DEPRECATED_curationPercentage;

    /// @dev Percentage of fees burned as protocol fee
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    /// Deprecated, now enforced by each data service (verifier)
    uint32 internal __DEPRECATED_protocolPercentage;

    /// @dev Period for allocation to be finalized
    uint32 private __DEPRECATED_channelDisputeEpochs; // solhint-disable-line var-name-mixedcase

    /// @dev Maximum allocation time
    uint32 internal __DEPRECATED_maxAllocationEpochs;

    /// @dev Rebate alpha numerator
    /// Originally used for Cobb-Douglas rebates, now used for exponential rebates
    /// Deprecated, now applied on the SubgraphService
    uint32 internal __DEPRECATED_alphaNumerator;

    /// @dev Rebate alpha denominator
    /// Originally used for Cobb-Douglas rebates, now used for exponential rebates
    /// Deprecated, now applied on the SubgraphService
    uint32 internal __DEPRECATED_alphaDenominator;

    /// @dev Service provider stakes : serviceProviderAddress => ServiceProvider
    mapping(address => ServiceProviderInternal) internal __serviceProviders;

    /// @dev Allocations : allocationID => Allocation
    /// Deprecated, now applied on the SubgraphService
    mapping(address => IStakingData.Allocation) internal __DEPRECATED_allocations;

    /// @dev Subgraph Allocations: subgraphDeploymentID => tokens
    /// Deprecated, now applied on the SubgraphService
    mapping(bytes32 => uint256) internal __DEPRECATED_subgraphAllocations;

    // Rebate pools : epoch => Pool
    mapping(uint256 => uint256) private __DEPRECATED_rebates; // solhint-disable-line var-name-mixedcase

    // -- Slashing --

    /// @dev List of addresses allowed to slash stakes
    /// Deprecated, now allowlisted by each service provider by setting a verifier
    mapping(address => bool) internal __DEPRECATED_slashers;

    // -- Delegation --

    /// @dev Set the delegation capacity multiplier defined by the delegation ratio
    /// If delegation ratio is 100, and an Indexer has staked 5 GRT,
    /// then they can use up to 500 GRT from the delegated stake
    uint32 internal __delegationRatio;

    /// @dev Time in blocks an indexer needs to wait to change delegation parameters (deprecated)
    uint32 internal __DEPRECATED_delegationParametersCooldown; // solhint-disable-line var-name-mixedcase

    /// @dev Time in epochs a delegator needs to wait to withdraw delegated stake
    /// Deprecated, now only enforced during a transition period
    uint32 internal __DEPRECATED_delegationUnbondingPeriod; // in epochs

    /// @dev Percentage of tokens to tax a delegation deposit
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    /// Deprecated, no tax is applied now.
    uint32 internal __DEPRECATED_delegationTaxPercentage;

    /// @dev Delegation pools : serviceProvider => DelegationPool
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
    /// Data services may optionally use this to determine where to send a service provider's
    /// fees or rewards, or restake them if this is empty.
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
    address internal __DEPRECATED_extensionImpl;
}

/**
 * @title StakingV4Storage
 * @notice This contract holds all the storage variables for the base Staking contract, version 4.
 */
contract StakingV4Storage is StakingV3Storage {
    // Additional rebate parameters for exponential rebates
    uint32 internal __DEPRECATED_lambdaNumerator;
    uint32 internal __DEPRECATED_lambdaDenominator;
}

/** 
 * @title StakingV5Storage
 * @notice First "Horizon" version of Staking storage
 * @dev Note that it includes a storage gap - if adding future versions, make sure to move the gap
 * to the new version and reduce the size of the gap accordingly.
 */
contract StakingV5Storage is StakingV4Storage {
    /// Verifier allowlist by service provider
    /// 0: not allowed
    /// any other value: verifier allowed at this timestamp
    /// serviceProvider => verifier => timestamp
    mapping(address => mapping(address => uint256)) public verifierAllowlist;

    /// Time in seconds an indexer must wait before they are allowed to create provisions for new verifiers
    uint256 public verifierTimelock;

    /// Time in seconds a delegator must wait since delegating before they are allowed to undelegate
    uint256 public undelegateTimelock;

    /// Maximum thawing period, in seconds, for a provision
    uint64 public maxThawingPeriod;

    /// @dev Provisions from each service provider for each data service
    mapping(bytes32 => Provision) internal provisions;

    /// @dev Gap to allow adding variables in future upgrades (since L1Staking and L2Staking can have their own storage as well)
    uint256[45] private __gap;
}
