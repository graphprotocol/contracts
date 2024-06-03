// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

/**
 * @title Interface for {HorizonStakingExtension} contract.
 * @notice Provides functions for managing legacy allocations and transfer tools.
 */
interface IHorizonStakingExtension {
    /**
     * @dev Allocate GRT tokens for the purpose of serving queries of a subgraph deployment
     * An allocation is created in the allocate() function and closed in closeAllocation()
     */
    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 closedAtEpoch; // Epoch when it was closed
        uint256 collectedFees; // Collected fees for the allocation
        uint256 __DEPRECATED_effectiveAllocation; // solhint-disable-line var-name-mixedcase
        uint256 accRewardsPerAllocatedToken; // Snapshot used for reward calc
        uint256 distributedRebates; // Collected rebates that have been rebated
    }

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
     * @notice Emitted when a delegator delegates through the Graph Token Gateway using the transfer tools.
     * @dev TODO(after transfer tools): delete
     * @param serviceProvider The address of the service provider.
     * @param delegator The address of the delegator.
     * @param tokens The amount of tokens delegated.
     */
    event StakeDelegated(address indexed serviceProvider, address indexed delegator, uint256 tokens, uint256 shares);

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

    event CounterpartStakingAddressSet(address indexed counterpart);

    /**
     * @notice Set the address of the counterpart (L1 or L2) staking contract.
     * @dev This function can only be called by the governor.
     * @param counterpart Address of the counterpart staking contract in the other chain, without any aliasing.
     */
    function setCounterpartStakingAddress(address counterpart) external;

    /**
     * @notice Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out of rewards set _poi to 0x0
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
     * @notice Return the allocation by ID.
     * @param allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address allocationID) external view returns (Allocation memory);

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

    /**
     * @notice Retrun the time in blocks to unstake
     * @return Thawing period in blocks
     */
    function __DEPRECATED_getThawingPeriod() external view returns (uint64);
}
