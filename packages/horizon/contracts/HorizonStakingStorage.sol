// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { Managed } from "./Managed.sol";
import { IStakingBackwardsCompatibility } from "./IStakingBackwardsCompatibility.sol";
import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";

/**
 * @title HorizonStakingV1Storage
 * @notice This contract holds all the storage variables for the Staking contract, version 1
 * @dev Note that we use a double underscore prefix for variable names; this prefix identifies
 * variables that used to be public but are now internal, getters can be found on StakingExtension.sol.
 */
// solhint-disable-next-line max-states-count
abstract contract HorizonStakingV1Storage is Managed, IHorizonStakingTypes {
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
    mapping(address => ServiceProviderInternal) internal serviceProviders;

    /// @dev Allocations : allocationID => Allocation
    /// Deprecated, now applied on the SubgraphService
    mapping(address => IStakingBackwardsCompatibility.Allocation) internal __DEPRECATED_allocations;

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
    uint32 internal delegationRatio;

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
    /// These are for the subgraph data service.
    mapping(address => DelegationPool) internal legacyDelegationPools;

    // -- Operators --

    /// @dev Legacy operator auth : indexer => operator => is authorized
    mapping(address => mapping(address => bool)) internal legacyOperatorAuth;

    // -- Asset Holders --

    /// @dev DEPRECATED: Allowed AssetHolders: assetHolder => is allowed
    mapping(address => bool) private __DEPRECATED_assetHolders; // solhint-disable-line var-name-mixedcase

    /// @dev Destination of accrued rewards : beneficiary => rewards destination
    /// Data services may optionally use this to determine where to send a service provider's
    /// fees or rewards, or restake them if this is empty.
    mapping(address => address) internal rewardsDestination;

    /// @dev Address of the counterpart Staking contract on L1/L2
    address internal counterpartStakingAddress;
    /// @dev Address of the StakingExtension implementation
    address internal __DEPRECATED_extensionImpl;

    // Additional rebate parameters for exponential rebates
    uint32 internal __DEPRECATED_lambdaNumerator;
    uint32 internal __DEPRECATED_lambdaDenominator;

    /// Verifier allowlist by service provider
    /// serviceProvider => verifier => allowed
    mapping(address => mapping(address => bool)) public verifierAllowlist;

    /// Maximum thawing period, in seconds, for a provision
    uint64 public maxThawingPeriod;

    /// @dev Provisions from each service provider for each data service
    /// ServiceProvider => Verifier => Provision
    mapping(address => mapping(address => Provision)) internal provisions;

    /// @dev Delegation fee cuts for each service provider on each provision, by fee type:
    /// ServiceProvider => Verifier => Fee Type => Fee Cut.
    /// This is the effective delegator fee cuts for each (data-service-defined) fee type (e.g. indexing fees, query fees).
    /// This is in PPM and is the cut taken by the indexer from the fees that correspond to delegators.
    /// (based on stake vs delegated stake proportion).
    /// The cuts are applied in GraphPayments so apply to all data services that use it.
    mapping(address => mapping(address => mapping(uint256 => uint256))) public delegationFeeCut;

    mapping(bytes32 => ThawRequest) internal thawRequests;

    // indexer => operator => authorized
    mapping(address => mapping(address => bool)) internal globalOperatorAuth;

    // indexer => verifier => operator => authorized
    mapping(address => mapping(address => mapping(address => bool))) internal operatorAuth;

    // governance enables or disables delegation slashing with this flag
    bool public delegationSlashingEnabled;

    // delegation pools for each service provider and verifier
    mapping(address => mapping(address => DelegationPool)) internal delegationPools;
}
