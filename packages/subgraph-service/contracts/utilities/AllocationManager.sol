// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { IAllocationManager } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";

import { GraphDirectory } from "@graphprotocol/horizon/contracts/utilities/GraphDirectory.sol";
import { AllocationManagerV1Storage } from "./AllocationManagerStorage.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

/**
 * @title AllocationManager contract
 * @author Edge & Node
 * @notice A helper contract implementing allocation lifecycle management
 * Allows opening, resizing, and closing allocations, as well as collecting indexing rewards by presenting a Proof
 * of Indexing (POI).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AllocationManager is
    IAllocationManager,
    EIP712Upgradeable,
    GraphDirectory,
    AllocationManagerV1Storage
{
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => IAllocation.State);
    using Allocation for IAllocation.State;
    using LegacyAllocation for mapping(address => ILegacyAllocation.State);
    using PPMMath for uint256;
    using TokenUtils for IGraphToken;

    ///@dev EIP712 typehash for allocation id proof
    bytes32 private constant EIP712_ALLOCATION_ID_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");
    // solhint-disable-previous-line gas-small-strings

    // forge-lint: disable-next-item(mixed-case-function)
    /**
     * @notice Initializes the contract and parent contracts
     * @param _name The name to use for EIP712 domain separation
     * @param _version The version to use for EIP712 domain separation
     */
    function __AllocationManager_init(string memory _name, string memory _version) internal onlyInitializing {
        __EIP712_init(_name, _version);
        __AllocationManager_init_unchained();
    }

    // forge-lint: disable-next-item(mixed-case-function)
    /**
     * @notice Initializes the contract
     */
    function __AllocationManager_init_unchained() internal onlyInitializing {}

    /**
     * @notice Imports a legacy allocation id into the subgraph service
     * This is a governor only action that is required to prevent indexers from re-using allocation ids from the
     * legacy staking contract. It will revert with LegacyAllocationAlreadyMigrated if the allocation has already been migrated.
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     * @param _subgraphDeploymentId The id of the subgraph deployment
     */
    function _migrateLegacyAllocation(address _indexer, address _allocationId, bytes32 _subgraphDeploymentId) internal {
        _legacyAllocations.migrate(_indexer, _allocationId, _subgraphDeploymentId);
        emit LegacyAllocationMigrated(_indexer, _allocationId, _subgraphDeploymentId);
    }

    /**
     * @notice Create an allocation
     * @dev The `_allocationProof` is a 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationId)`
     *
     * Requirements:
     * - `_allocationId` must not be the zero address
     *
     * Emits a {AllocationCreated} event
     *
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation to be created
     * @param _subgraphDeploymentId The subgraph deployment Id
     * @param _tokens The amount of tokens to allocate
     * @param _allocationProof Signed proof of allocation id address ownership
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     */
    function _allocate(
        address _indexer,
        address _allocationId,
        bytes32 _subgraphDeploymentId,
        uint256 _tokens,
        bytes memory _allocationProof,
        uint32 _delegationRatio
    ) internal {
        require(_allocationId != address(0), AllocationManagerInvalidZeroAllocationId());

        _verifyAllocationProof(_indexer, _allocationId, _allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on allocations.create()) and legacy allocations
        _legacyAllocations.revertIfExists(_graphStaking(), _allocationId);

        uint256 currentEpoch = _graphEpochManager().currentEpoch();
        IAllocation.State memory allocation = _allocations.create(
            _indexer,
            _allocationId,
            _subgraphDeploymentId,
            _tokens,
            _graphRewardsManager().onSubgraphAllocationUpdate(_subgraphDeploymentId),
            currentEpoch
        );

        // Check that the indexer has enough tokens available
        // Note that the delegation ratio ensures overdelegation cannot be used
        allocationProvisionTracker.lock(_graphStaking(), _indexer, _tokens, _delegationRatio);

        // Update total allocated tokens for the subgraph deployment
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] + allocation.tokens;

        emit AllocationCreated(_indexer, _allocationId, _subgraphDeploymentId, allocation.tokens, currentEpoch);
    }

    /**
     * @notice Present a POI to collect indexing rewards for an allocation
     * Mints indexing rewards using the {RewardsManager} and distributes them to the indexer and delegators.
     *
     * Requirements for indexing rewards:
     * - POI must be non-zero
     * - POI must not be stale (older than `maxPOIStaleness`)
     * - Allocation must be open for at least one epoch (returns early with 0 if too young)
     *
     * When rewards cannot be claimed, they are reclaimed with reason STALE_POI or ZERO_POI.
     * Altruistic allocations and too-young allocations skip reclaim (nothing to reclaim / allow claiming later).
     *
     * Note: Indexers should present POIs at least every `maxPOIStaleness` to avoid being locked out of rewards.
     * A zero POI can be presented if a valid one is unavailable, to prevent staleness and slashing.
     *
     * Note: Reclaim address changes in RewardsManager apply retroactively to all unclaimed rewards.
     *
     * Emits a {IndexingRewardsCollected} event.
     *
     * @param _allocationId The id of the allocation to collect rewards for
     * @param _poi The POI being presented
     * @param _poiMetadata Metadata associated with the POI, emitted as-is for off-chain components
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _paymentsDestination The address where indexing rewards should be sent
     * @return rewardsCollected Indexing rewards collected
     */
    // solhint-disable-next-line function-max-lines
    function _presentPoi(
        address _allocationId,
        bytes32 _poi,
        bytes memory _poiMetadata,
        uint32 _delegationRatio,
        address _paymentsDestination
    ) internal returns (uint256 rewardsCollected) {
        IAllocation.State memory allocation = _allocations.get(_allocationId);
        require(allocation.isOpen(), AllocationManagerAllocationClosed(_allocationId));
        _allocations.presentPOI(_allocationId); // Always record POI presentation to prevent staleness
        // Scoped for stack management
        {
            // Determine rewards condition
            bytes32 condition = RewardsCondition.NONE;
            if (allocation.isStale(maxPOIStaleness)) condition = RewardsCondition.STALE_POI;
            else if (_poi == bytes32(0))
                condition = RewardsCondition.ZERO_POI;
                // solhint-disable-next-line gas-strict-inequalities
            else if (_graphEpochManager().currentEpoch() <= allocation.createdAtEpoch)
                condition = RewardsCondition.ALLOCATION_TOO_YOUNG;
            else if (_graphRewardsManager().isDenied(allocation.subgraphDeploymentId))
                condition = RewardsCondition.SUBGRAPH_DENIED;

            emit POIPresented(
                allocation.indexer,
                _allocationId,
                allocation.subgraphDeploymentId,
                _poi,
                _poiMetadata,
                condition
            );

            // Early return skips the overallocation check intentionally to avoid loss of uncollected rewards
            if (condition == RewardsCondition.ALLOCATION_TOO_YOUNG || condition == RewardsCondition.SUBGRAPH_DENIED)
                return 0;

            bool rewardsReclaimable = condition == RewardsCondition.STALE_POI || condition == RewardsCondition.ZERO_POI;
            if (rewardsReclaimable) _graphRewardsManager().reclaimRewards(condition, _allocationId);
            else rewardsCollected = _graphRewardsManager().takeRewards(_allocationId);
        }

        // Snapshot rewards to prevent accumulation for next POI, then clear pending
        _allocations.snapshotRewards(
            _allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        _allocations.clearPendingRewards(_allocationId);

        // Scoped for stack management
        {
            (uint256 tokensIndexerRewards, uint256 tokensDelegationRewards) = _distributeIndexingRewards(
                allocation,
                rewardsCollected,
                _paymentsDestination
            );

            emit IndexingRewardsCollected(
                allocation.indexer,
                _allocationId,
                allocation.subgraphDeploymentId,
                rewardsCollected,
                tokensIndexerRewards,
                tokensDelegationRewards,
                _poi,
                _poiMetadata,
                _graphEpochManager().currentEpoch()
            );
        }

        if (_isOverAllocated(allocation.indexer, _delegationRatio)) _closeAllocation(_allocationId, true);
    }

    /**
     * @notice Resize an allocation
     * @dev Will lock or release tokens in the provision tracker depending on the new allocation size.
     * Rewards accrued but not issued before the resize will be accounted for as pending rewards.
     * These will be paid out when the indexer presents a POI.
     *
     * Requirements:
     * - `_indexer` must be the owner of the allocation
     * - Allocation must be open
     * - `_tokens` must be different from the current allocation size
     *
     * Emits a {AllocationResized} event.
     *
     * @param _allocationId The id of the allocation to be resized
     * @param _tokens The new amount of tokens to allocate
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     */
    function _resizeAllocation(address _allocationId, uint256 _tokens, uint32 _delegationRatio) internal {
        IAllocation.State memory allocation = _allocations.get(_allocationId);
        require(allocation.isOpen(), AllocationManagerAllocationClosed(_allocationId));
        require(_tokens != allocation.tokens, AllocationManagerAllocationSameSize(_allocationId, _tokens));

        // Update provision tracker
        uint256 oldTokens = allocation.tokens;
        if (_tokens > oldTokens) {
            allocationProvisionTracker.lock(_graphStaking(), allocation.indexer, _tokens - oldTokens, _delegationRatio);
        } else {
            allocationProvisionTracker.release(allocation.indexer, oldTokens - _tokens);
        }

        // Calculate rewards that have been accrued since the last snapshot but not yet issued
        uint256 accRewardsPerAllocatedToken = _graphRewardsManager().onSubgraphAllocationUpdate(
            allocation.subgraphDeploymentId
        );
        uint256 accRewardsPerAllocatedTokenPending = !allocation.isAltruistic()
            ? accRewardsPerAllocatedToken - allocation.accRewardsPerAllocatedToken
            : 0;

        // Update the allocation
        _allocations[_allocationId].tokens = _tokens;
        _allocations[_allocationId].accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        _allocations[_allocationId].accRewardsPending += _graphRewardsManager().calcRewards(
            oldTokens,
            accRewardsPerAllocatedTokenPending
        );

        // Update total allocated tokens for the subgraph deployment
        if (_tokens > oldTokens) {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] += (_tokens - oldTokens);
        } else {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] -= (oldTokens - _tokens);
        }

        emit AllocationResized(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, _tokens, oldTokens);
    }

    /**
     * @notice Close an allocation
     * Does not require presenting a POI, use {_collectIndexingRewards} to present a POI and collect rewards
     * @dev Note that allocations are nowlong lived. All service payments, including indexing rewards, should be collected periodically
     * without the need of closing the allocation. Allocations should only be closed when indexers want to reclaim the allocated
     * tokens for other purposes.
     *
     * Emits a {AllocationClosed} event
     *
     * @param _allocationId The id of the allocation to be closed
     * @param _forceClosed Whether the allocation was force closed
     */
    function _closeAllocation(address _allocationId, bool _forceClosed) internal {
        IAllocation.State memory allocation = _allocations.get(_allocationId);

        // Reclaim uncollected rewards before closing
        uint256 reclaimedRewards = _graphRewardsManager().reclaimRewards(
            RewardsCondition.CLOSE_ALLOCATION,
            _allocationId
        );

        // Take rewards snapshot to prevent other allos from counting tokens from this allo
        _allocations.snapshotRewards(
            _allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
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

        emit AllocationClosed(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            _forceClosed
        );
    }

    /**
     * @notice Sets the maximum amount of time, in seconds, allowed between presenting POIs to qualify for indexing rewards
     * @dev Emits a {MaxPOIStalenessSet} event
     * @param _maxPoiStaleness The max POI staleness in seconds
     */
    function _setMaxPoiStaleness(uint256 _maxPoiStaleness) internal {
        maxPOIStaleness = _maxPoiStaleness;
        emit MaxPOIStalenessSet(_maxPoiStaleness);
    }

    /**
     * @notice Encodes the allocation proof for EIP712 signing
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     * @return The encoded allocation proof
     */
    function _encodeAllocationProof(address _indexer, address _allocationId) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_ID_PROOF_TYPEHASH, _indexer, _allocationId)));
    }

    /**
     * @notice Checks if an allocation is over-allocated
     * @param _indexer The address of the indexer
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @return True if the allocation is over-allocated, false otherwise
     */
    function _isOverAllocated(address _indexer, uint32 _delegationRatio) internal view returns (bool) {
        return !allocationProvisionTracker.check(_graphStaking(), _indexer, _delegationRatio);
    }

    /**
     * @notice Distributes indexing rewards to delegators and indexer
     * @param _allocation The allocation state
     * @param _rewardsCollected Total rewards to distribute
     * @param _paymentsDestination Where to send indexer rewards (0 = stake)
     * @return tokensIndexerRewards Amount sent to indexer
     * @return tokensDelegationRewards Amount sent to delegation pool
     */
    function _distributeIndexingRewards(
        IAllocation.State memory _allocation,
        uint256 _rewardsCollected,
        address _paymentsDestination
    ) private returns (uint256 tokensIndexerRewards, uint256 tokensDelegationRewards) {
        if (_rewardsCollected == 0) return (0, 0);

        // Calculate and distribute delegator share
        uint256 delegatorCut = _graphStaking().getDelegationFeeCut(
            _allocation.indexer,
            address(this),
            IGraphPayments.PaymentTypes.IndexingRewards
        );
        IHorizonStakingTypes.DelegationPool memory pool = _graphStaking().getDelegationPool(
            _allocation.indexer,
            address(this)
        );
        tokensDelegationRewards = pool.shares > 0 ? _rewardsCollected.mulPPM(delegatorCut) : 0;
        if (tokensDelegationRewards > 0) {
            _graphToken().approve(address(_graphStaking()), tokensDelegationRewards);
            _graphStaking().addToDelegationPool(_allocation.indexer, address(this), tokensDelegationRewards);
        }

        // Distribute indexer share
        tokensIndexerRewards = _rewardsCollected - tokensDelegationRewards;
        if (tokensIndexerRewards > 0) {
            if (_paymentsDestination == address(0)) {
                _graphToken().approve(address(_graphStaking()), tokensIndexerRewards);
                _graphStaking().stakeToProvision(_allocation.indexer, address(this), tokensIndexerRewards);
            } else {
                _graphToken().pushTokens(_paymentsDestination, tokensIndexerRewards);
            }
        }
    }

    /**
     * @notice Verifies ownership of an allocation id by verifying an EIP712 allocation proof
     * @dev Requirements:
     * - Signer must be the allocation id address
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     * @param _proof The EIP712 proof, an EIP712 signed message of (indexer,allocationId)
     */
    function _verifyAllocationProof(address _indexer, address _allocationId, bytes memory _proof) private view {
        address signer = ECDSA.recover(_encodeAllocationProof(_indexer, _allocationId), _proof);
        require(signer == _allocationId, AllocationManagerInvalidAllocationProof(signer, _allocationId));
    }
}
