// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;
pragma abicoder v2;

import { IStakingData } from "./IStakingData.sol";

/**
 * @title Base interface for the Staking contract.
 * @dev This interface includes only what's implemented in the base Staking contract.
 * It does not include the L1 and L2 specific functionality. It also does not include
 * several functions that are implemented in the StakingExtension contract, and are called
 * via delegatecall through the fallback function. See IStaking.sol for an interface
 * that includes the full functionality.
 */
interface IStakingBase is IStakingData {
    /**
     * @dev Emitted when `indexer` stakes `tokens` amount.
     */
    event StakeDeposited(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` unstaked and locked `tokens` amount until `until` block.
     */
    event StakeLocked(address indexed indexer, uint256 tokens, uint256 until);

    /**
     * @dev Emitted when `indexer` withdrew `tokens` staked.
     */
    event StakeWithdrawn(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphDeploymentID`
     * during `epoch`.
     * `allocationID` indexer derived address used to identify the allocation.
     * `metadata` additional information related to the allocation.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address indexed allocationID,
        bytes32 metadata
    );

    /**
     * @dev Emitted when `indexer` close an allocation in `epoch` for `allocationID`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentID`.
     * This event also emits the POI (proof of indexing) submitted by the indexer.
     * `isPublic` is true if the sender was someone other than the indexer.
     */
    event AllocationClosed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address indexed allocationID,
        address sender,
        bytes32 poi,
        bool isPublic
    );

    /**
     * @dev Emitted when `indexer` collects a rebate on `subgraphDeploymentID` for `allocationID`.
     * `epoch` is the protocol epoch the rebate was collected on
     * The rebate is for `tokens` amount which are being provided by `assetHolder`; `queryFees`
     * is the amount up for rebate after `curationFees` are distributed and `protocolTax` is burnt.
     * `queryRebates` is the amount distributed to the `indexer` with `delegationFees` collected
     * and sent to the delegation pool.
     */
    event RebateCollected(
        address assetHolder,
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        address indexed allocationID,
        uint256 epoch,
        uint256 tokens,
        uint256 protocolTax,
        uint256 curationFees,
        uint256 queryFees,
        uint256 queryRebates,
        uint256 delegationRewards
    );

    /**
     * @dev Emitted when `indexer` update the delegation parameters for its delegation pool.
     */
    event DelegationParametersUpdated(
        address indexed indexer,
        uint32 indexingRewardCut,
        uint32 queryFeeCut,
        uint32 __DEPRECATED_cooldownBlocks // solhint-disable-line var-name-mixedcase
    );

    /**
     * @dev Emitted when `indexer` set `operator` access.
     */
    event SetOperator(address indexed indexer, address indexed operator, bool allowed);

    /**
     * @dev Emitted when `indexer` set an address to receive rewards.
     */
    event SetRewardsDestination(address indexed indexer, address indexed destination);

    /**
     * @dev Emitted when `extensionImpl` was set as the address of the StakingExtension contract
     * to which extended functionality is delegated.
     */
    event ExtensionImplementationSet(address indexed extensionImpl);

    /**
     * @dev Possible states an allocation can be.
     * States:
     * - Null = indexer == address(0)
     * - Active = not Null && tokens > 0
     * - Closed = Active && closedAtEpoch != 0
     */
    enum AllocationState {
        Null,
        Active,
        Closed
    }

    /**
     * @notice Initialize this contract.
     * @param controller Address of the controller that manages this contract
     * @param minimumIndexerStake Minimum amount of tokens that an indexer must stake
     * @param thawingPeriod Number of blocks that tokens get locked after unstaking
     * @param protocolPercentage Percentage of query fees that are burned as protocol fee (in PPM)
     * @param curationPercentage Percentage of query fees that are given to curators (in PPM)
     * @param maxAllocationEpochs The maximum number of epochs that an allocation can be active
     * @param delegationUnbondingPeriod The period in epochs that tokens get locked after undelegating
     * @param delegationRatio The ratio between an indexer's own stake and the delegation they can use
     * @param rebatesParameters Alpha and lambda parameters for rebates function
     * @param extensionImpl Address of the StakingExtension implementation
     */
    function initialize(
        address controller,
        uint256 minimumIndexerStake,
        uint32 thawingPeriod,
        uint32 protocolPercentage,
        uint32 curationPercentage,
        uint32 maxAllocationEpochs,
        uint32 delegationUnbondingPeriod,
        uint32 delegationRatio,
        RebatesParameters calldata rebatesParameters,
        address extensionImpl
    ) external;

    /**
     * @notice Set the address of the StakingExtension implementation.
     * @dev This function can only be called by the governor.
     * @param extensionImpl Address of the StakingExtension implementation
     */
    function setExtensionImpl(address extensionImpl) external;

    /**
     * @notice Set the address of the counterpart (L1 or L2) staking contract.
     * @dev This function can only be called by the governor.
     * @param counterpart Address of the counterpart staking contract in the other chain, without any aliasing.
     */
    function setCounterpartStakingAddress(address counterpart) external;

    /**
     * @notice Set the minimum stake needed to be an Indexer
     * @dev This function can only be called by the governor.
     * @param minimumIndexerStake Minimum amount of tokens that an indexer must stake
     */
    function setMinimumIndexerStake(uint256 minimumIndexerStake) external;

    /**
     * @notice Set the number of blocks that tokens get locked after unstaking
     * @dev This function can only be called by the governor.
     * @param thawingPeriod Number of blocks that tokens get locked after unstaking
     */
    function setThawingPeriod(uint32 thawingPeriod) external;

    /**
     * @notice Set the curation percentage of query fees sent to curators.
     * @dev This function can only be called by the governor.
     * @param percentage Percentage of query fees sent to curators
     */
    function setCurationPercentage(uint32 percentage) external;

    /**
     * @notice Set a protocol percentage to burn when collecting query fees.
     * @dev This function can only be called by the governor.
     * @param percentage Percentage of query fees to burn as protocol fee
     */
    function setProtocolPercentage(uint32 percentage) external;

    /**
     * @notice Set the max time allowed for indexers to allocate on a subgraph
     * before others are allowed to close the allocation.
     * @dev This function can only be called by the governor.
     * @param maxAllocationEpochs Allocation duration limit in epochs
     */
    function setMaxAllocationEpochs(uint32 maxAllocationEpochs) external;

    /**
     * @notice Set the rebate parameters
     * @dev This function can only be called by the governor.
     * @param alphaNumerator Numerator of `alpha`
     * @param alphaDenominator Denominator of `alpha`
     * @param lambdaNumerator Numerator of `lambda`
     * @param lambdaDenominator Denominator of `lambda`
     */
    function setRebateParameters(
        uint32 alphaNumerator,
        uint32 alphaDenominator,
        uint32 lambdaNumerator,
        uint32 lambdaDenominator
    ) external;

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller.
     * @param operator Address to authorize or unauthorize
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address operator, bool allowed) external;

    /**
     * @notice Deposit tokens on the indexer's stake.
     * The amount staked must be over the minimumIndexerStake.
     * @param tokens Amount of tokens to stake
     */
    function stake(uint256 tokens) external;

    /**
     * @notice Deposit tokens on the Indexer stake, on behalf of the Indexer.
     * The amount staked must be over the minimumIndexerStake.
     * @param indexer Address of the indexer
     * @param tokens Amount of tokens to stake
     */
    function stakeTo(address indexer, uint256 tokens) external;

    /**
     * @notice Unstake tokens from the indexer stake, lock them until the thawing period expires.
     * @dev NOTE: The function accepts an amount greater than the currently staked tokens.
     * If that happens, it will try to unstake the max amount of tokens it can.
     * The reason for this behaviour is to avoid time conditions while the transaction
     * is in flight.
     * @param tokens Amount of tokens to unstake
     */
    function unstake(uint256 tokens) external;

    /**
     * @notice Withdraw indexer tokens once the thawing period has passed.
     */
    function withdraw() external;

    /**
     * @notice Set the destination where to send rewards for an indexer.
     * @param destination Rewards destination address. If set to zero, rewards will be restaked
     */
    function setRewardsDestination(address destination) external;

    /**
     * @notice Set the delegation parameters for the caller.
     * @param indexingRewardCut Percentage of indexing rewards left for the indexer
     * @param queryFeeCut Percentage of query fees left for the indexer
     */
    function setDelegationParameters(
        uint32 indexingRewardCut,
        uint32 queryFeeCut,
        uint32 // cooldownBlocks, deprecated
    ) external;

    /**
     * @notice Allocate available tokens to a subgraph deployment.
     * @param subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param tokens Amount of tokens to allocate
     * @param allocationID The allocation identifier
     * @param metadata IPFS hash for additional information about the allocation
     * @param proof A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`
     */
    function allocate(
        bytes32 subgraphDeploymentID,
        uint256 tokens,
        address allocationID,
        bytes32 metadata,
        bytes calldata proof
    ) external;

    /**
     * @notice Allocate available tokens to a subgraph deployment from and indexer's stake.
     * The caller must be the indexer or the indexer's operator.
     * @param indexer Indexer address to allocate funds from.
     * @param subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param tokens Amount of tokens to allocate
     * @param allocationID The allocation identifier
     * @param metadata IPFS hash for additional information about the allocation
     * @param proof A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`
     */
    function allocateFrom(
        address indexer,
        bytes32 subgraphDeploymentID,
        uint256 tokens,
        address allocationID,
        bytes32 metadata,
        bytes calldata proof
    ) external;

    /**
     * @notice Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out of rewards set poi to 0x0
     * @param allocationID The allocation identifier
     * @param poi Proof of indexing submitted for the allocated period
     */
    function closeAllocation(address allocationID, bytes32 poi) external;

    /**
     * @notice Collect query fees from state channels and assign them to an allocation.
     * Funds received are only accepted from a valid sender.
     * @dev To avoid reverting on the withdrawal from channel flow this function will:
     * 1) Accept calls with zero tokens.
     * 2) Accept calls after an allocation passed the dispute period, in that case, all
     *    the received tokens are burned.
     * @param tokens Amount of tokens to collect
     * @param allocationID Allocation where the tokens will be assigned
     */
    function collect(uint256 tokens, address allocationID) external;

    /**
     * @notice Return true if operator is allowed for indexer.
     * @param operator Address of the operator
     * @param indexer Address of the indexer
     * @return True if operator is allowed for indexer, false otherwise
     */
    function isOperator(address operator, address indexer) external view returns (bool);

    /**
     * @notice Getter that returns if an indexer has any stake.
     * @param indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address indexer) external view returns (bool);

    /**
     * @notice Get the total amount of tokens staked by the indexer.
     * @param indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address indexer) external view returns (uint256);

    /**
     * @notice Get the total amount of tokens available to use in allocations.
     * This considers the indexer stake and delegated tokens according to delegation ratio
     * @param indexer Address of the indexer
     * @return Amount of tokens available to allocate including delegation
     */
    function getIndexerCapacity(address indexer) external view returns (uint256);

    /**
     * @notice Return the allocation by ID.
     * @param allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address allocationID) external view returns (Allocation memory);

    /**
     * @dev New function to get the allocation data for the rewards manager
     * @dev Note that this is only to make tests pass, as the staking contract with
     * this changes will never get deployed. HorizonStaking is taking it's place.
     */
    function getAllocationData(
        address allocationID
    ) external view returns (bool, address, bytes32, uint256, uint256, uint256);

    /**
     * @dev New function to get the allocation active status for the rewards manager
     * @dev Note that this is only to make tests pass, as the staking contract with
     * this changes will never get deployed. HorizonStaking is taking it's place.
     */
    function isActiveAllocation(address allocationID) external view returns (bool);

    /**
     * @notice Return the current state of an allocation
     * @param allocationID Allocation identifier
     * @return AllocationState enum with the state of the allocation
     */
    function getAllocationState(address allocationID) external view returns (AllocationState);

    /**
     * @notice Return if allocationID is used.
     * @param allocationID Address used as signer by the indexer for an allocation
     * @return True if allocationID already used
     */
    function isAllocation(address allocationID) external view returns (bool);

    /**
     * @notice Return the total amount of tokens allocated to subgraph.
     * @param subgraphDeploymentID Deployment ID for the subgraph
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 subgraphDeploymentID) external view returns (uint256);
}
