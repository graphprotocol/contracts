// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";

/**
 * @title Interface for {HorizonStakingExtension} contract.
 * @notice Provides functions for managing legacy allocations.
 */
interface IHorizonStakingExtension is IRewardsIssuer {
    /**
     * @dev Allocate GRT tokens for the purpose of serving queries of a subgraph deployment
     * An allocation is created in the allocate() function and closed in closeAllocation()
     * @param indexer The indexer address
     * @param subgraphDeploymentID The subgraph deployment ID
     * @param tokens The amount of tokens allocated to the subgraph deployment
     * @param createdAtEpoch The epoch when the allocation was created
     * @param closedAtEpoch The epoch when the allocation was closed
     * @param collectedFees The amount of collected fees for the allocation
     * @param __DEPRECATED_effectiveAllocation Deprecated field.
     * @param accRewardsPerAllocatedToken Snapshot used for reward calculation
     * @param distributedRebates The amount of collected rebates that have been rebated
     */
    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens;
        uint256 createdAtEpoch;
        uint256 closedAtEpoch;
        uint256 collectedFees;
        uint256 __DEPRECATED_effectiveAllocation;
        uint256 accRewardsPerAllocatedToken;
        uint256 distributedRebates;
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
     * @dev Emitted when `indexer` close an allocation in `epoch` for `allocationID`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentID`.
     * This event also emits the POI (proof of indexing) submitted by the indexer.
     * `isPublic` is true if the sender was someone other than the indexer.
     * @param indexer The indexer address
     * @param subgraphDeploymentID The subgraph deployment ID
     * @param epoch The protocol epoch the allocation was closed on
     * @param tokens The amount of tokens unallocated from the allocation
     * @param allocationID The allocation identifier
     * @param sender The address closing the allocation
     * @param poi The proof of indexing submitted by the sender
     * @param isPublic True if the allocation was force closed by someone other than the indexer/operator
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
     * @param assetHolder The address of the asset holder, the entity paying the query fees
     * @param indexer The indexer address
     * @param subgraphDeploymentID The subgraph deployment ID
     * @param allocationID The allocation identifier
     * @param epoch The protocol epoch the rebate was collected on
     * @param tokens The amount of tokens collected
     * @param protocolTax The amount of tokens burnt as protocol tax
     * @param curationFees The amount of tokens distributed to the curation pool
     * @param queryFees The amount of tokens collected as query fees
     * @param queryRebates The amount of tokens distributed to the indexer
     * @param delegationRewards The amount of tokens collected from the delegation pool
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
     * @dev Emitted when `indexer` was slashed for a total of `tokens` amount.
     * Tracks `reward` amount of tokens given to `beneficiary`.
     * @param indexer The indexer address
     * @param tokens The amount of tokens slashed
     * @param reward The amount of reward tokens to send to a beneficiary
     * @param beneficiary The address of a beneficiary to receive a reward for the slashing
     */
    event StakeSlashed(address indexed indexer, uint256 tokens, uint256 reward, address beneficiary);

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
     * @dev Collect and rebate query fees to the indexer
     * This function will accept calls with zero tokens.
     * We use an exponential rebate formula to calculate the amount of tokens to rebate to the indexer.
     * This implementation allows collecting multiple times on the same allocation, keeping track of the
     * total amount rebated, the total amount collected and compensating the indexer for the difference.
     * @param tokens Amount of tokens to collect
     * @param allocationID Allocation where the tokens will be assigned
     */
    function collect(uint256 tokens, address allocationID) external;

    /**
     * @notice Slash the indexer stake. Delegated tokens are not subject to slashing.
     * @dev Can only be called by the slasher role.
     * @param indexer Address of indexer to slash
     * @param tokens Amount of tokens to slash from the indexer stake
     * @param reward Amount of reward tokens to send to a beneficiary
     * @param beneficiary Address of a beneficiary to receive a reward for the slashing
     */
    function legacySlash(address indexer, uint256 tokens, uint256 reward, address beneficiary) external;

    /**
     * @notice (Legacy) Return true if operator is allowed for the service provider on the subgraph data service.
     * @param operator Address of the operator
     * @param indexer Address of the service provider
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
     * @notice Return the time in blocks to unstake
     * Deprecated, now enforced by each data service (verifier)
     * @return Thawing period in blocks
     */
    function __DEPRECATED_getThawingPeriod() external view returns (uint64);

    /**
     * @notice Return the address of the subgraph data service.
     * @dev TRANSITION PERIOD: After transition period move to main HorizonStaking contract
     * @return Address of the subgraph data service
     */
    function getSubgraphService() external view returns (address);
}
