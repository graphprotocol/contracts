// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { IHorizonStakingExtension } from "../interfaces/internal/IHorizonStakingExtension.sol";
import { IHorizonStakingTypes } from "../interfaces/internal/IHorizonStakingTypes.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { LinkedList } from "../libraries/LinkedList.sol";

/* solhint-disable var-name-mixedcase */ // TODO: create custom var-name-mixedcase
/* solhint-disable max-states-count */

/**
 * @title HorizonStakingV1Storage
 * @notice This contract holds all the storage variables for the Staking contract.
 * @dev Deprecated variables are kept to support the transition to Horizon Staking.
 * They can eventually be collapsed into a single storage slot.
 */
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
    /// Deprecated with exponential rebates.
    uint32 private __DEPRECATED_channelDisputeEpochs;

    /// @dev Maximum allocation time.
    /// Deprecated, allocations now live on the subgraph service contract.
    uint32 internal __DEPRECATED_maxAllocationEpochs;

    /// @dev Rebate alpha numerator
    /// Originally used for Cobb-Douglas rebates, now used for exponential rebates
    /// Deprecated, any rebate mechanism is now applied on the subgraph data service.
    uint32 internal __DEPRECATED_alphaNumerator;

    /// @dev Rebate alpha denominator
    /// Originally used for Cobb-Douglas rebates, now used for exponential rebates
    /// Deprecated, any rebate mechanism is now applied on the subgraph data service.
    uint32 internal __DEPRECATED_alphaDenominator;

    /// @dev Service providers details, tracks stake utilization.
    mapping(address serviceProvider => IHorizonStakingTypes.ServiceProviderInternal details) internal _serviceProviders;

    /// @dev Allocation details.
    /// Deprecated, now applied on the subgraph data service
    mapping(address allocationId => IHorizonStakingExtension.Allocation allocation) internal __DEPRECATED_allocations;

    /// @dev Subgraph allocations, tracks the tokens allocated to a subgraph deployment
    /// Deprecated, now applied on the SubgraphService
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) internal __DEPRECATED_subgraphAllocations;

    /// @dev Rebate pool details per epoch
    /// Deprecated with exponential rebates.
    mapping(uint256 epoch => uint256 rebates) private __DEPRECATED_rebates;

    // -- Slashing --

    /// @dev List of addresses allowed to slash stakes
    /// Deprecated, now each verifier can slash the corresponding provision.
    mapping(address slasher => bool allowed) internal __DEPRECATED_slashers;

    // -- Delegation --

    /// @dev Delegation capacity multiplier defined by the delegation ratio
    /// Deprecated, enforced by each data service as needed.
    uint32 internal __DEPRECATED_delegationRatio;

    /// @dev Time in blocks an indexer needs to wait to change delegation parameters
    /// Deprecated, enforced by each data service as needed.
    uint32 internal __DEPRECATED_delegationParametersCooldown;

    /// @dev Time in epochs a delegator needs to wait to withdraw delegated stake
    /// Deprecated, now only enforced during a transition period
    uint32 internal __DEPRECATED_delegationUnbondingPeriod;

    /// @dev Percentage of tokens to tax a delegation deposit
    /// Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    /// Deprecated, no tax is applied now.
    uint32 internal __DEPRECATED_delegationTaxPercentage;

    /// @dev Delegation pools (legacy).
    /// Only used when the verifier is the subgraph data service.
    mapping(address serviceProvider => IHorizonStakingTypes.DelegationPoolInternal delegationPool)
        internal _legacyDelegationPools;

    // -- Operators --

    /// @dev Operator allow list (legacy)
    /// Only used when the verifier is the subgraph data service.
    mapping(address serviceProvider => mapping(address legacyOperator => bool authorized)) internal _legacyOperatorAuth;

    // -- Asset Holders --

    /// @dev Asset holder allow list
    /// Deprecated with permissionless payers
    mapping(address assetHolder => bool allowed) private __DEPRECATED_assetHolders;

    /// @dev Destination of accrued indexing rewards
    /// Deprecated, defined by each data service as needed
    mapping(address serviceProvider => address rewardsDestination) internal __DEPRECATED_rewardsDestination;

    /// @dev Address of the counterpart Staking contract on L1/L2
    /// Used for the transfer tools.
    address internal _counterpartStakingAddress;

    /// @dev Address of the StakingExtension implementation
    /// This is now an immutable variable to save some gas.
    address internal __DEPRECATED_extensionImpl;

    // @dev Additional rebate parameters for exponential rebates
    /// Deprecated, any rebate mechanism is now applied on the subgraph data service.
    uint32 internal __DEPRECATED_lambdaNumerator;
    uint32 internal __DEPRECATED_lambdaDenominator;

    // -- Horizon Staking --

    /// @dev Maximum thawing period, in seconds, for a provision
    uint64 internal _maxThawingPeriod;

    /// @dev Provisions from each service provider for each data service
    mapping(address serviceProvider => mapping(address verifier => IHorizonStakingTypes.Provision provision))
        internal _provisions;

    /// @dev Delegation fee cuts for each service provider on each provision, by fee type:
    /// This is the effective delegator fee cuts for each (data-service-defined) fee type (e.g. indexing fees, query fees).
    /// This is in PPM and is the cut taken by the service provider from the fees that correspond to delegators.
    /// (based on stake vs delegated stake proportion).
    /// The cuts are applied in GraphPayments so apply to all data services that use it.
    mapping(address serviceProvider => mapping(address verifier => mapping(IGraphPayments.PaymentTypes paymentType => uint256 feeCut)))
        internal _delegationFeeCut;

    /// @dev Thaw requests
    /// Details for each thawing operation in the staking contract (for both service providers and delegators).
    mapping(bytes32 thawRequestId => IHorizonStakingTypes.ThawRequest thawRequest) internal _thawRequests;

    /// @dev Thaw request lists
    /// Metadata defining linked lists of thaw requests for each service provider or delegator (owner)
    mapping(address serviceProvider => mapping(address verifier => mapping(address owner => LinkedList.List list)))
        internal _thawRequestLists;

    /// @dev Operator allow list
    /// Used for all verifiers except the subgraph data service.
    mapping(address serviceProvider => mapping(address verifier => mapping(address operator => bool authorized)))
        internal _operatorAuth;

    /// @dev Flag to enable or disable delegation slashing
    bool internal _delegationSlashingEnabled;

    /// @dev Delegation pools for each service provider and verifier
    mapping(address serviceProvider => mapping(address verifier => IHorizonStakingTypes.DelegationPoolInternal delegationPool))
        internal _delegationPools;

    /// @dev Allowed verifiers for locked provisions (i.e. from GraphTokenLockWallets)
    // Verifiers are whitelisted to ensure locked tokens cannot escape using an arbitrary verifier.
    mapping(address verifier => bool allowed) internal _allowedLockedVerifiers;
}
