// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IEpochManager } from "@graphprotocol/interfaces/contracts/contracts/epochs/IEpochManager.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

/**
 * @title AllocationHandler contract
 * @author Edge & Node
 * @notice A helper contract implementing allocation lifecycle management.
 * Allows opening, resizing, and closing allocations, as well as collecting indexing rewards by presenting a Proof
 * of Indexing (POI).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library AllocationHandler {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => IAllocation.State);
    using Allocation for IAllocation.State;
    using LegacyAllocation for mapping(address => ILegacyAllocation.State);
    using PPMMath for uint256;
    using TokenUtils for IGraphToken;

    /**
     * @notice Parameters for the allocation creation
     * @param currentEpoch The current epoch at the time of allocation creation
     * @param graphStaking The Horizon staking contract to handle token locking
     * @param graphRewardsManager The rewards manager to handle rewards distribution
     * @param _encodeAllocationProof The EIP712 encoded allocation proof
     * @param _indexer The address of the indexer creating the allocation
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _allocationId The id of the allocation to be created
     * @param _subgraphDeploymentId The id of the subgraph deployment for which the allocation is created
     * @param _tokens The amount of tokens to allocate
     * @param _allocationProof The EIP712 proof, an EIP712 signed message of (indexer,allocationId)
     */
    struct AllocateParams {
        uint256 currentEpoch;
        IHorizonStaking graphStaking;
        IRewardsManager graphRewardsManager;
        bytes32 _encodeAllocationProof;
        address _indexer;
        uint32 _delegationRatio;
        address _allocationId;
        bytes32 _subgraphDeploymentId;
        uint256 _tokens;
        bytes _allocationProof;
    }

    /**
     * @notice Parameters for the POI presentation
     * @param maxPOIStaleness The maximum staleness of the POI in epochs
     * @param graphEpochManager The epoch manager to get the current epoch
     * @param graphStaking The Horizon staking contract to handle token locking
     * @param graphRewardsManager The rewards manager to handle rewards distribution
     * @param graphToken The Graph token contract to handle token transfers
     * @param dataService The data service address (for delegation pool lookups)
     * @param _allocationId The id of the allocation for which the POI is presented
     * @param _poi The proof of indexing (POI) to be presented
     * @param _poiMetadata The metadata associated with the POI
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _paymentsDestination The address to which the indexing rewards should be sent
     */
    struct PresentParams {
        uint256 maxPOIStaleness;
        IEpochManager graphEpochManager;
        IHorizonStaking graphStaking;
        IRewardsManager graphRewardsManager;
        IGraphToken graphToken;
        address dataService;
        address _allocationId;
        bytes32 _poi;
        bytes _poiMetadata;
        uint32 _delegationRatio;
        address _paymentsDestination;
    }

    /**
     * @notice Emitted when an indexer creates an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     * @param currentEpoch The current epoch
     */
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        uint256 currentEpoch
    );

    /**
     * @notice Emitted when an indexer collects indexing rewards for an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokensRewards The amount of tokens collected
     * @param tokensIndexerRewards The amount of tokens collected for the indexer
     * @param tokensDelegationRewards The amount of tokens collected for delegators
     * @param poi The POI presented
     * @param poiMetadata The metadata associated with the POI
     * @param currentEpoch The current epoch
     */
    event IndexingRewardsCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards,
        bytes32 poi,
        bytes poiMetadata,
        uint256 currentEpoch
    );

    /**
     * @notice Emitted when an indexer resizes an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param newTokens The new amount of tokens allocated
     * @param oldTokens The old amount of tokens allocated
     */
    event AllocationResized(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 newTokens,
        uint256 oldTokens
    );

    /**
     * @notice Emitted when an indexer closes an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     * @param forceClosed Whether the allocation was force closed
     */
    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens,
        bool forceClosed
    );

    /**
     * @notice Emitted when a legacy allocation is migrated into the subgraph service
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     */
    event LegacyAllocationMigrated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId
    );

    /**
     * @notice Emitted when the maximum POI staleness is updated
     * @param maxPOIStaleness The max POI staleness in seconds
     */
    event MaxPOIStalenessSet(uint256 maxPOIStaleness);
    // solhint-disable-previous-line gas-indexed-events

    /**
     * @notice Emitted when an indexer presents a POI for an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param poi The POI presented
     * @param poiMetadata The metadata associated with the POI
     * @param condition The rewards condition determined for this POI
     */
    event POIPresented(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        bytes32 poi,
        bytes poiMetadata,
        bytes32 condition
    );

    /**
     * @notice Thrown when an allocation proof is invalid
     * Both `signer` and `allocationId` should match for a valid proof.
     * @param signer The address that signed the proof
     * @param allocationId The id of the allocation
     */
    error AllocationHandlerInvalidAllocationProof(address signer, address allocationId);

    /**
     * @notice Thrown when attempting to create an allocation with a zero allocation id
     */
    error AllocationHandlerInvalidZeroAllocationId();

    /**
     * @notice Thrown when attempting to collect indexing rewards on a closed allocation
     * @param allocationId The id of the allocation
     */
    error AllocationHandlerAllocationClosed(address allocationId);

    /**
     * @notice Thrown when attempting to resize an allocation with the same size
     * @param allocationId The id of the allocation
     * @param tokens The amount of tokens
     */
    error AllocationHandlerAllocationSameSize(address allocationId, uint256 tokens);

    /**
     * @notice Create an allocation
     * @dev The `_allocationProof` is a 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationId)`
     *
     * Requirements:
     * - `_allocationId` must not be the zero address
     *
     * Emits a {AllocationCreated} event
     *
     * @param _allocations The mapping of allocation ids to allocation states
     * @param _legacyAllocations The mapping of legacy allocation ids to legacy allocation states
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param _subgraphAllocatedTokens The mapping of subgraph deployment ids to their allocated tokens
     * @param params The parameters for the allocation
     */
    function allocate(
        mapping(address allocationId => IAllocation.State allocation) storage _allocations,
        mapping(address allocationId => ILegacyAllocation.State allocation) storage _legacyAllocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        AllocateParams calldata params
    ) external {
        require(params._allocationId != address(0), AllocationHandler.AllocationHandlerInvalidZeroAllocationId());

        _verifyAllocationProof(params._encodeAllocationProof, params._allocationId, params._allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on allocations.create()) and legacy allocations
        _legacyAllocations.revertIfExists(params._allocationId);

        IAllocation.State memory allocation = _allocations.create(
            params._indexer,
            params._allocationId,
            params._subgraphDeploymentId,
            params._tokens,
            params.graphRewardsManager.onSubgraphAllocationUpdate(params._subgraphDeploymentId),
            params.currentEpoch
        );

        // Check that the indexer has enough tokens available
        // Note that the delegation ratio ensures overdelegation cannot be used
        allocationProvisionTracker.lock(params.graphStaking, params._indexer, params._tokens, params._delegationRatio);

        // Update total allocated tokens for the subgraph deployment
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] + allocation.tokens;

        emit AllocationHandler.AllocationCreated(
            params._indexer,
            params._allocationId,
            params._subgraphDeploymentId,
            allocation.tokens,
            params.currentEpoch
        );
    }

    /* solhint-disable function-max-lines */
    /**
     * @notice Present a POI to collect indexing rewards for an allocation
     * Mints indexing rewards using the {RewardsManager} and distributes them to the indexer and delegators.
     *
     * Requirements for indexing rewards:
     * - POI must be non-zero
     * - POI must not be stale (older than `maxPOIStaleness`)
     * - Allocation must be open for at least one epoch (returns early with 0 if too young)
     *
     * ## Reward Paths
     *
     * Rewards follow one of three paths based on allocation and POI state:
     *
     * **CLAIMED** (normal path): Valid POI, not stale, allocation mature, subgraph not denied
     * - Calls `takeRewards()` to mint tokens to this contract
     * - Distributes to indexer (stake or payments destination) and delegators
     * - Snapshots allocation to prevent double-counting
     *
     * **RECLAIMED** (redirect path): STALE_POI or ZERO_POI conditions
     * - Calls `reclaimRewards()` to mint tokens to configured reclaim address
     * - If no reclaim address configured, rewards are dropped (not minted)
     * - Snapshots allocation to prevent double-counting
     *
     * **DEFERRED** (early return): ALLOCATION_TOO_YOUNG or SUBGRAPH_DENIED conditions
     * - Returns 0 without calling take or reclaim
     * - Does NOT snapshot allocation (preserves rewards for later collection)
     * - Allows rewards to be claimed when condition clears
     *
     * Emits a {POIPresented} event.
     * Emits a {IndexingRewardsCollected} event.
     *
     * @param _allocations The mapping of allocation ids to allocation states
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param _subgraphAllocatedTokens The mapping of subgraph deployment ids to their allocated tokens
     * @param params The parameters for the POI presentation
     * @return rewardsCollected The amount of tokens collected
     * @return allocationForceClosed True if the allocation was automatically closed due to over-allocation, false otherwise
     */
    function presentPOI(
        mapping(address allocationId => IAllocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        PresentParams calldata params
    ) external returns (uint256 rewardsCollected, bool allocationForceClosed) {
        IAllocation.State memory allocation = _allocations.get(params._allocationId);
        require(allocation.isOpen(), AllocationHandler.AllocationHandlerAllocationClosed(params._allocationId));
        _allocations.presentPOI(params._allocationId); // Always record POI presentation to prevent staleness

        uint256 currentEpoch = params.graphEpochManager.currentEpoch();
        // Scoped for stack management
        {
            // Determine rewards condition
            bytes32 condition = RewardsCondition.NONE;
            if (allocation.isStale(params.maxPOIStaleness)) condition = RewardsCondition.STALE_POI;
            else if (params._poi == bytes32(0))
                condition = RewardsCondition.ZERO_POI;
                // solhint-disable-next-line gas-strict-inequalities
            else if (currentEpoch <= allocation.createdAtEpoch) condition = RewardsCondition.ALLOCATION_TOO_YOUNG;
            else if (params.graphRewardsManager.isDenied(allocation.subgraphDeploymentId))
                condition = RewardsCondition.SUBGRAPH_DENIED;

            emit AllocationHandler.POIPresented(
                allocation.indexer,
                params._allocationId,
                allocation.subgraphDeploymentId,
                params._poi,
                params._poiMetadata,
                condition
            );

            // Early return skips the overallocation check intentionally to avoid loss of uncollected rewards
            if (condition == RewardsCondition.ALLOCATION_TOO_YOUNG || condition == RewardsCondition.SUBGRAPH_DENIED) {
                // Keep reward and reclaim accumulation current even if rewards are not collected
                params.graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId);

                return (0, false);
            }

            bool rewardsReclaimable = condition == RewardsCondition.STALE_POI || condition == RewardsCondition.ZERO_POI;
            if (rewardsReclaimable) params.graphRewardsManager.reclaimRewards(condition, params._allocationId);
            else rewardsCollected = params.graphRewardsManager.takeRewards(params._allocationId);
        }

        // Snapshot rewards to prevent accumulation for next POI, then clear pending
        _allocations.snapshotRewards(
            params._allocationId,
            params.graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        _allocations.clearPendingRewards(params._allocationId);

        // Scoped for stack management
        {
            (uint256 tokensIndexerRewards, uint256 tokensDelegationRewards) = _distributeIndexingRewards(
                allocation,
                rewardsCollected,
                params
            );

            emit AllocationHandler.IndexingRewardsCollected(
                allocation.indexer,
                params._allocationId,
                allocation.subgraphDeploymentId,
                rewardsCollected,
                tokensIndexerRewards,
                tokensDelegationRewards,
                params._poi,
                params._poiMetadata,
                currentEpoch
            );
        }

        // Check if the indexer is over-allocated and force close the allocation if necessary
        if (
            _isOverAllocated(
                allocationProvisionTracker,
                params.graphStaking,
                allocation.indexer,
                params._delegationRatio
            )
        ) {
            allocationForceClosed = true;
            _closeAllocation(
                _allocations,
                allocationProvisionTracker,
                _subgraphAllocatedTokens,
                params.graphRewardsManager,
                params._allocationId,
                true
            );
        }
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Close an allocation
     * Does not require presenting a POI, use {_collectIndexingRewards} to present a POI and collect rewards
     * @dev Note that allocations are long lived. All service payments, including indexing rewards, should be collected periodically
     * without the need of closing the allocation. Allocations should only be closed when indexers want to reclaim the allocated
     * tokens for other purposes.
     *
     * Emits a {AllocationClosed} event
     *
     * @param _allocations The mapping of allocation ids to allocation states
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param _subgraphAllocatedTokens The mapping of subgraph deployment ids to their allocated tokens
     * @param graphRewardsManager The rewards manager to handle rewards distribution
     * @param _allocationId The id of the allocation to be closed
     * @param _forceClosed Whether the allocation was force closed
     */
    function closeAllocation(
        mapping(address allocationId => IAllocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        IRewardsManager graphRewardsManager,
        address _allocationId,
        bool _forceClosed
    ) external {
        _closeAllocation(
            _allocations,
            allocationProvisionTracker,
            _subgraphAllocatedTokens,
            graphRewardsManager,
            _allocationId,
            _forceClosed
        );
    }

    /* solhint-disable function-max-lines */
    /**
     * @notice Resize an allocation
     * @dev Will lock or release tokens in the provision tracker depending on the new allocation size.
     * Rewards accrued but not issued before the resize will be accounted for as pending rewards,
     * unless the allocation is stale, in which case pending rewards are reclaimed.
     * These will be paid out when the indexer presents a POI.
     *
     * Requirements:
     * - `_indexer` must be the owner of the allocation
     * - Allocation must be open
     * - `_tokens` must be different from the current allocation size
     *
     * Emits a {AllocationResized} event.
     *
     * @param _allocations The mapping of allocation ids to allocation states
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param _subgraphAllocatedTokens The mapping of subgraph deployment ids to their allocated tokens
     * @param graphStaking The Horizon staking contract to handle token locking
     * @param graphRewardsManager The rewards manager to handle rewards distribution
     * @param _allocationId The id of the allocation to be resized
     * @param _tokens The new amount of tokens to allocate
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _maxPOIStaleness The maximum staleness of the POI in seconds
     */
    function resizeAllocation(
        mapping(address allocationId => IAllocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        IHorizonStaking graphStaking,
        IRewardsManager graphRewardsManager,
        address _allocationId,
        uint256 _tokens,
        uint32 _delegationRatio,
        uint256 _maxPOIStaleness
    ) external {
        IAllocation.State memory allocation = _allocations.get(_allocationId);
        require(allocation.isOpen(), AllocationHandler.AllocationHandlerAllocationClosed(_allocationId));
        require(
            _tokens != allocation.tokens,
            AllocationHandler.AllocationHandlerAllocationSameSize(_allocationId, _tokens)
        );

        // Update provision tracker
        uint256 oldTokens = allocation.tokens;
        if (_tokens > oldTokens) {
            allocationProvisionTracker.lock(graphStaking, allocation.indexer, _tokens - oldTokens, _delegationRatio);
        } else {
            allocationProvisionTracker.release(allocation.indexer, oldTokens - _tokens);
        }

        // Calculate rewards that have been accrued since the last snapshot but not yet issued
        uint256 accRewardsPerAllocatedToken = graphRewardsManager.onSubgraphAllocationUpdate(
            allocation.subgraphDeploymentId
        );
        uint256 accRewardsPerAllocatedTokenPending = !allocation.isAltruistic()
            ? accRewardsPerAllocatedToken - allocation.accRewardsPerAllocatedToken
            : 0;

        // Update the allocation
        _allocations[_allocationId].tokens = _tokens;
        _allocations[_allocationId].accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        _allocations[_allocationId].accRewardsPending += graphRewardsManager.calcRewards(
            oldTokens,
            accRewardsPerAllocatedTokenPending
        );

        // If allocation is stale, reclaim pending rewards defensively.
        // Stale allocations are not performing, so rewards should not accumulate.
        if (allocation.isStale(_maxPOIStaleness)) {
            graphRewardsManager.reclaimRewards(RewardsCondition.STALE_POI, _allocationId);
            _allocations.clearPendingRewards(_allocationId);
        }

        // Update total allocated tokens for the subgraph deployment
        if (_tokens > oldTokens) {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] += (_tokens - oldTokens);
        } else {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] -= (oldTokens - _tokens);
        }

        emit AllocationHandler.AllocationResized(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            _tokens,
            oldTokens
        );
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Checks if an allocation is over-allocated
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param graphStaking The Horizon staking contract to check delegation ratios
     * @param _indexer The address of the indexer
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @return True if the allocation is over-allocated, false otherwise
     */
    function isOverAllocated(
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        IHorizonStaking graphStaking,
        address _indexer,
        uint32 _delegationRatio
    ) external view returns (bool) {
        return _isOverAllocated(allocationProvisionTracker, graphStaking, _indexer, _delegationRatio);
    }

    /**
     * @notice Close an allocation (internal)
     * @dev Reclaims uncollected rewards before closing.
     *
     * Emits a {AllocationClosed} event
     *
     * @param _allocations The mapping of allocation ids to allocation states
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param _subgraphAllocatedTokens The mapping of subgraph deployment ids to their allocated tokens
     * @param graphRewardsManager The rewards manager to handle rewards distribution
     * @param _allocationId The id of the allocation to be closed
     * @param _forceClosed Whether the allocation was force closed
     */
    function _closeAllocation(
        mapping(address allocationId => IAllocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        IRewardsManager graphRewardsManager,
        address _allocationId,
        bool _forceClosed
    ) private {
        IAllocation.State memory allocation = _allocations.get(_allocationId);

        // Reclaim uncollected rewards before closing
        uint256 reclaimedRewards = graphRewardsManager.reclaimRewards(RewardsCondition.CLOSE_ALLOCATION, _allocationId);

        // Take rewards snapshot to prevent other allos from counting tokens from this allo
        _allocations.snapshotRewards(
            _allocationId,
            graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );

        // Clear pending rewards only if rewards were reclaimed. This marks them as consumed,
        // which could be useful for future logic that searches for unconsumed rewards.
        // Known limitation: This capture is incomplete due to other code paths (e.g., _presentPOI)
        // that clear pending even when rewards are not consumed.
        if (0 < reclaimedRewards) _allocations.clearPendingRewards(_allocationId);

        _allocations.close(_allocationId);
        allocationProvisionTracker.release(allocation.indexer, allocation.tokens);

        // Update total allocated tokens for the subgraph deployment
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] - allocation.tokens;

        emit AllocationHandler.AllocationClosed(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            _forceClosed
        );
    }

    /**
     * @notice Distributes indexing rewards to delegators and indexer
     * @param _allocation The allocation state
     * @param _rewardsCollected Total rewards to distribute
     * @param _params The present params containing staking, token, and destination info
     * @return tokensIndexerRewards Amount sent to indexer
     * @return tokensDelegationRewards Amount sent to delegation pool
     */
    function _distributeIndexingRewards(
        IAllocation.State memory _allocation,
        uint256 _rewardsCollected,
        PresentParams memory _params
    ) private returns (uint256 tokensIndexerRewards, uint256 tokensDelegationRewards) {
        if (_rewardsCollected == 0) return (0, 0);

        // Calculate and distribute delegator share
        uint256 delegatorCut = _params.graphStaking.getDelegationFeeCut(
            _allocation.indexer,
            _params.dataService,
            IGraphPayments.PaymentTypes.IndexingRewards
        );
        IHorizonStakingTypes.DelegationPool memory pool = _params.graphStaking.getDelegationPool(
            _allocation.indexer,
            _params.dataService
        );
        tokensDelegationRewards = pool.shares > 0 ? _rewardsCollected.mulPPM(delegatorCut) : 0;
        if (tokensDelegationRewards > 0) {
            _params.graphToken.approve(address(_params.graphStaking), tokensDelegationRewards);
            _params.graphStaking.addToDelegationPool(_allocation.indexer, _params.dataService, tokensDelegationRewards);
        }

        // Distribute indexer share
        tokensIndexerRewards = _rewardsCollected - tokensDelegationRewards;
        if (tokensIndexerRewards > 0) {
            if (_params._paymentsDestination == address(0)) {
                _params.graphToken.approve(address(_params.graphStaking), tokensIndexerRewards);
                _params.graphStaking.stakeToProvision(_allocation.indexer, _params.dataService, tokensIndexerRewards);
            } else {
                _params.graphToken.pushTokens(_params._paymentsDestination, tokensIndexerRewards);
            }
        }
    }

    /**
     * @notice Checks if an allocation is over-allocated
     * @param allocationProvisionTracker The mapping of indexers to their locked tokens
     * @param graphStaking The Horizon staking contract to check delegation ratios
     * @param _indexer The address of the indexer
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @return True if the allocation is over-allocated, false otherwise
     */
    function _isOverAllocated(
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        IHorizonStaking graphStaking,
        address _indexer,
        uint32 _delegationRatio
    ) private view returns (bool) {
        return !allocationProvisionTracker.check(graphStaking, _indexer, _delegationRatio);
    }

    /**
     * @notice Verifies ownership of an allocation id by verifying an EIP712 allocation proof
     * @dev Requirements:
     * - Signer must be the allocation id address
     * @param _encodeAllocationProof The EIP712 encoded allocation proof
     * @param _allocationId The id of the allocation
     * @param _proof The EIP712 proof, an EIP712 signed message of (indexer,allocationId)
     */
    function _verifyAllocationProof(
        bytes32 _encodeAllocationProof,
        address _allocationId,
        bytes memory _proof
    ) private pure {
        address signer = ECDSA.recover(_encodeAllocationProof, _proof);
        require(
            signer == _allocationId,
            AllocationHandler.AllocationHandlerInvalidAllocationProof(signer, _allocationId)
        );
    }
}
