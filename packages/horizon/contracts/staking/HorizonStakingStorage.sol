// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IStakingBackwardsCompatibility } from "../interfaces/IStakingBackwardsCompatibility.sol";
import { IHorizonStakingTypes } from "../interfaces/IHorizonStakingTypes.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

// TODO: create custom var-name-mixedcase
/* solhint-disable var-name-mixedcase */

/**
 * @title HorizonStakingV1Storage
 * @notice This contract holds all the storage variables for the Staking contract, version 1
 */
// solhint-disable-next-line max-states-count
abstract contract HorizonStakingV1Storage {
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
    uint32 private __DEPRECATED_channelDisputeEpochs;

    /// @dev Maximum allocation time. Deprecated, allocations now live on the subgraph service contract.
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
    mapping(address serviceProvider => IHorizonStakingTypes.ServiceProviderInternal details) internal _serviceProviders;

    /// @dev Allocations : allocationID => Allocation
    /// Deprecated, now applied on the SubgraphService
    mapping(address allocationId => IStakingBackwardsCompatibility.Allocation allocation)
        internal __DEPRECATED_allocations;

    /// @dev Subgraph Allocations: subgraphDeploymentID => tokens
    /// Deprecated, now applied on the SubgraphService
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) internal __DEPRECATED_subgraphAllocations;

    /// @dev Rebate pools : epoch => Pool
    /// Deprecated.
    mapping(uint256 epoch => uint256 rebates) private __DEPRECATED_rebates;

    // -- Slashing --

    /// @dev List of addresses allowed to slash stakes
    /// Deprecated, now each verifier can slash the corresponding provision.
    mapping(address slasher => bool allowed) internal __DEPRECATED_slashers;

    // -- Delegation --

    /// @dev Delegation capacity multiplier defined by the delegation ratio
    /// Deprecated, now applied by each data service as needed.
    uint32 internal __DEPRECATED_delegationRatio;

    /// @dev Time in blocks an indexer needs to wait to change delegation parameters (deprecated)
    uint32 internal __DEPRECATED_delegationParametersCooldown;

    /// @dev Time in epochs a delegator needs to wait to withdraw delegated stake
    /// Deprecated, now only enforced during a transition period
    uint32 internal __DEPRECATED_delegationUnbondingPeriod; // in epochs

    /// @dev Percentage of tokens to tax a delegation deposit
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    /// Deprecated, no tax is applied now.
    uint32 internal __DEPRECATED_delegationTaxPercentage;

    /// @dev Delegation pools : serviceProvider => DelegationPoolInternal
    /// These are for the subgraph data service.
    mapping(address serviceProvider => IHorizonStakingTypes.DelegationPoolInternal delegationPool)
        internal _legacyDelegationPools;

    // -- Operators --

    /// @dev Legacy operator auth : indexer => operator => is authorized
    mapping(address legacyOperator => mapping(address serviceProvider => bool authorized)) internal _legacyOperatorAuth;

    // -- Asset Holders --

    /// @dev DEPRECATED: Allowed AssetHolders: assetHolder => is allowed
    mapping(address assetHolder => bool allowed) private __DEPRECATED_assetHolders;

    /// @dev Destination of accrued rewards : beneficiary => rewards destination
    /// Deprecated, defined by each data service as needed
    mapping(address serviceProvider => address rewardsDestination) internal __DEPRECATED_rewardsDestination;

    /// @dev Address of the counterpart Staking contract on L1/L2
    address internal _counterpartStakingAddress;
    /// @dev Address of the StakingExtension implementation
    address internal __DEPRECATED_extensionImpl;

    // Additional rebate parameters for exponential rebates
    uint32 internal __DEPRECATED_lambdaNumerator;
    uint32 internal __DEPRECATED_lambdaDenominator;

    /// Maximum thawing period, in seconds, for a provision
    uint64 internal _maxThawingPeriod;

    /// @dev Provisions from each service provider for each data service
    /// ServiceProvider => Verifier => Provision
    mapping(address serviceProvider => mapping(address verifier => IHorizonStakingTypes.Provision provision))
        internal _provisions;

    /// @dev Delegation fee cuts for each service provider on each provision, by fee type:
    /// ServiceProvider => Verifier => Payment Type => Fee Cut.
    /// This is the effective delegator fee cuts for each (data-service-defined) fee type (e.g. indexing fees, query fees).
    /// This is in PPM and is the cut taken by the indexer from the fees that correspond to delegators.
    /// (based on stake vs delegated stake proportion).
    /// The cuts are applied in GraphPayments so apply to all data services that use it.
    mapping(address serviceProvider => mapping(address verifier => mapping(IGraphPayments.PaymentTypes paymentType => uint256 feeCut)))
        public delegationFeeCut;

    mapping(bytes32 thawRequestId => IHorizonStakingTypes.ThawRequest thawRequest) internal _thawRequests;

    // indexer => verifier => operator => authorized
    mapping(address serviceProvider => mapping(address verifier => mapping(address operator => bool authorized)))
        internal _operatorAuth;

    // governance enables or disables delegation slashing with this flag
    bool public delegationSlashingEnabled;

    // delegation pools for each service provider and verifier
    mapping(address serviceProvider => mapping(address verifier => IHorizonStakingTypes.DelegationPoolInternal delegationPool))
        internal _delegationPools;

    // allowed verifiers for locked provisions (i.e. from GraphTokenLockWallets)
    mapping(address verifier => bool allowed) internal _allowedLockedVerifiers;
}
