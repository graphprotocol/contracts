// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";
import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { AllocationManager } from "../utilities/AllocationManager.sol";

library AllocationManagerLib {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;
    using LegacyAllocation for mapping(address => LegacyAllocation.State);
    using PPMMath for uint256;
    using TokenUtils for IGraphToken;

    struct AllocateParams {
        uint256 currentEpoch;
        IHorizonStaking graphStaking;
        IRewardsManager graphRewardsManager;
        bytes32 _encodeAllocationProof;
        address _indexer;
        address _allocationId;
        bytes32 _subgraphDeploymentId;
        uint256 _tokens;
        bytes _allocationProof;
        uint32 _delegationRatio;
    }

    struct PresentParams {
        uint256 maxPOIStaleness;
        IEpochManager graphEpochManager;
        IHorizonStaking graphStaking;
        IRewardsManager graphRewardsManager;
        IGraphToken graphToken;
        address _allocationId;
        bytes32 _poi;
        bytes _poiMetadata;
        uint32 _delegationRatio;
        address _paymentsDestination;
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
     * @param _allocations The mapping of allocation ids to allocation states
     */
    function allocate(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
        mapping(address allocationId => LegacyAllocation.State allocation) storage _legacyAllocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        AllocateParams memory params
    ) external {
        require(params._allocationId != address(0), AllocationManager.AllocationManagerInvalidZeroAllocationId());

        _verifyAllocationProof(params._encodeAllocationProof, params._allocationId, params._allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on allocations.create()) and legacy allocations
        _legacyAllocations.revertIfExists(params.graphStaking, params._allocationId);

        Allocation.State memory allocation = _allocations.create(
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
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            allocation.tokens;

        emit AllocationManager.AllocationCreated(
            params._indexer,
            params._allocationId,
            params._subgraphDeploymentId,
            allocation.tokens,
            params.currentEpoch
        );
    }

    function presentPOI(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        PresentParams memory params
    ) external returns (uint256) {
        Allocation.State memory allocation = _allocations.get(params._allocationId);
        require(allocation.isOpen(), AllocationManager.AllocationManagerAllocationClosed(params._allocationId));

        // Mint indexing rewards if all conditions are met
        uint256 tokensRewards = (!allocation.isStale(params.maxPOIStaleness) &&
            !allocation.isAltruistic() &&
            params._poi != bytes32(0)) && params.graphEpochManager.currentEpoch() > allocation.createdAtEpoch
            ? params.graphRewardsManager.takeRewards(params._allocationId)
            : 0;

        // ... but we still take a snapshot to ensure the rewards are not accumulated for the next valid POI
        _allocations.snapshotRewards(
            params._allocationId,
            params.graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        _allocations.presentPOI(params._allocationId);

        // Any pending rewards should have been collected now
        _allocations.clearPendingRewards(params._allocationId);

        uint256 tokensIndexerRewards = 0;
        uint256 tokensDelegationRewards = 0;
        if (tokensRewards != 0) {
            // Distribute rewards to delegators
            uint256 delegatorCut = params.graphStaking.getDelegationFeeCut(
                allocation.indexer,
                address(this),
                IGraphPayments.PaymentTypes.IndexingRewards
            );
            IHorizonStakingTypes.DelegationPool memory delegationPool = params.graphStaking.getDelegationPool(
                allocation.indexer,
                address(this)
            );
            // If delegation pool has no shares then we don't need to distribute rewards to delegators
            tokensDelegationRewards = delegationPool.shares > 0 ? tokensRewards.mulPPM(delegatorCut) : 0;
            if (tokensDelegationRewards > 0) {
                params.graphToken.approve(address(params.graphStaking), tokensDelegationRewards);
                params.graphStaking.addToDelegationPool(allocation.indexer, address(this), tokensDelegationRewards);
            }

            // Distribute rewards to indexer
            tokensIndexerRewards = tokensRewards - tokensDelegationRewards;
            if (tokensIndexerRewards > 0) {
                if (params._paymentsDestination == address(0)) {
                    params.graphToken.approve(address(params.graphStaking), tokensIndexerRewards);
                    params.graphStaking.stakeToProvision(allocation.indexer, address(this), tokensIndexerRewards);
                } else {
                    params.graphToken.pushTokens(params._paymentsDestination, tokensIndexerRewards);
                }
            }
        }

        emit AllocationManager.IndexingRewardsCollected(
            allocation.indexer,
            params._allocationId,
            allocation.subgraphDeploymentId,
            tokensRewards,
            tokensIndexerRewards,
            tokensDelegationRewards,
            params._poi,
            params._poiMetadata,
            params.graphEpochManager.currentEpoch()
        );

        // Check if the indexer is over-allocated and force close the allocation if necessary
        if (
            _isOverAllocated(
                allocationProvisionTracker,
                params.graphStaking,
                allocation.indexer,
                params._delegationRatio
            )
        ) {
            _closeAllocation(
                _allocations,
                allocationProvisionTracker,
                _subgraphAllocatedTokens,
                params.graphRewardsManager,
                params._allocationId,
                true
            );
        }

        return tokensRewards;
    }

    function closeAllocation(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
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
    function resizeAllocation(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        IHorizonStaking graphStaking,
        IRewardsManager graphRewardsManager,
        address _allocationId,
        uint256 _tokens,
        uint32 _delegationRatio
    ) external {
        Allocation.State memory allocation = _allocations.get(_allocationId);
        require(allocation.isOpen(), AllocationManager.AllocationManagerAllocationClosed(_allocationId));
        require(
            _tokens != allocation.tokens,
            AllocationManager.AllocationManagerAllocationSameSize(_allocationId, _tokens)
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

        // Update total allocated tokens for the subgraph deployment
        if (_tokens > oldTokens) {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] += (_tokens - oldTokens);
        } else {
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] -= (oldTokens - _tokens);
        }

        emit AllocationManager.AllocationResized(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            _tokens,
            oldTokens
        );
    }

    /**
     * @notice Checks if an allocation is over-allocated
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

    function _closeAllocation(
        mapping(address allocationId => Allocation.State allocation) storage _allocations,
        mapping(address indexer => uint256 tokens) storage allocationProvisionTracker,
        mapping(bytes32 subgraphDeploymentId => uint256 tokens) storage _subgraphAllocatedTokens,
        IRewardsManager graphRewardsManager,
        address _allocationId,
        bool _forceClosed
    ) private {
        Allocation.State memory allocation = _allocations.get(_allocationId);

        // Take rewards snapshot to prevent other allos from counting tokens from this allo
        _allocations.snapshotRewards(
            _allocationId,
            graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );

        _allocations.close(_allocationId);
        allocationProvisionTracker.release(allocation.indexer, allocation.tokens);

        // Update total allocated tokens for the subgraph deployment
        _subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            _subgraphAllocatedTokens[allocation.subgraphDeploymentId] -
            allocation.tokens;

        emit AllocationManager.AllocationClosed(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            allocation.tokens,
            _forceClosed
        );
    }

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
            AllocationManager.AllocationManagerInvalidAllocationProof(signer, _allocationId)
        );
    }
}
