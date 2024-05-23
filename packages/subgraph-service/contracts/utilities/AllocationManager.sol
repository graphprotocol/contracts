// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { GraphDirectory } from "@graphprotocol/horizon/contracts/data-service/GraphDirectory.sol";
import { AllocationManagerV1Storage } from "./AllocationManagerStorage.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";

abstract contract AllocationManager is EIP712, GraphDirectory, AllocationManagerV1Storage {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using LegacyAllocation for mapping(address => LegacyAllocation.State);
    using PPMMath for uint256;

    // -- Immutables --
    bytes32 private immutable EIP712_ALLOCATION_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphDeploymentId`
     * during `epoch`.
     * `allocationId` indexer derived address used to identify the allocation.
     */
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
    );

    event IndexingRewardsCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards,
        bytes32 poi
    );

    event AllocationResized(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 newTokens,
        uint256 oldTokens
    );

    /**
     * @dev Emitted when `indexer` closes an allocation with id `allocationId`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentId`.
     */
    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
    );

    event LegacyAllocationMigrated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId
    );

    event RewardsDestinationSet(address indexed indexer, address rewardsDestination);

    error AllocationManagerInvalidAllocationProof(address signer, address allocationId);
    error AllocationManagerInvalidAllocationId();
    error AllocationManagerZeroTokensAllocation(address allocationId);
    error AllocationManagerAllocationClosed(address allocationId);
    error AllocationManagerAllocationSameSize(address allocationId, uint256 tokens);
    error AllocationManagerInvalidZeroPOI();

    constructor(string memory name, string memory version) EIP712(name, version) {}

    function setRewardsDestination(address rewardsDestination) external {
        _setRewardsDestination(msg.sender, rewardsDestination);
    }

    function _migrateLegacyAllocation(address _indexer, address _allocationId, bytes32 _subgraphDeploymentId) internal {
        legacyAllocations.migrate(_indexer, _allocationId, _subgraphDeploymentId);
        emit LegacyAllocationMigrated(_indexer, _allocationId, _subgraphDeploymentId);
    }

    function _allocate(
        address _indexer,
        address _allocationId,
        bytes32 _subgraphDeploymentId,
        uint256 _tokens,
        bytes memory _allocationProof,
        uint32 _delegationRatio
    ) internal returns (Allocation.State memory) {
        if (_allocationId == address(0)) revert AllocationManagerInvalidAllocationId();

        _verifyAllocationProof(_indexer, _allocationId, _allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on create()) and legacy allocations
        legacyAllocations.revertIfExists(_allocationId);
        Allocation.State memory allocation = allocations.create(
            _indexer,
            _allocationId,
            _subgraphDeploymentId,
            _tokens,
            // allos can be resized now, so we need to always take snapshot
            _graphRewardsManager().onSubgraphAllocationUpdate(_subgraphDeploymentId)
        );

        // Check that the indexer has enough tokens available
        allocationProvisionTracker.lock(_graphStaking(), _indexer, _tokens, _delegationRatio);

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            allocation.tokens;

        emit AllocationCreated(_indexer, _allocationId, _subgraphDeploymentId, allocation.tokens);
        return allocation;
    }

    // Update POI timestamp and take rewards snapshot even for 0 rewards
    // This ensures the rewards are actually skipped and not collected with the next valid POI
    function _collectIndexingRewards(bytes memory _data) internal returns (uint256) {
        (address allocationId, bytes32 poi) = abi.decode(_data, (address, bytes32));

        Allocation.State memory allocation = allocations.get(allocationId);

        // Mint indexing rewards, 0x00 and stale POIs get no rewards...
        uint256 timeSinceLastPOI = block.number - Math.max(allocation.createdAt, allocation.lastPOIPresentedAt);
        uint256 tokensRewards = (timeSinceLastPOI <= maxPOIStaleness && poi != bytes32(0))
            ? _graphRewardsManager().takeRewards(allocationId)
            : 0;

        // ... but we still take a snapshot to ensure the rewards are not accumulated for the next valid POI
        allocations.snapshotRewards(
            allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        allocations.presentPOI(allocationId);

        // Any pending rewards should have been collected now
        allocations.clearPendingRewards(allocationId);

        if (tokensRewards == 0) {
            emit IndexingRewardsCollected(
                allocation.indexer,
                allocationId,
                allocation.subgraphDeploymentId,
                0,
                0,
                0,
                poi
            );
            return tokensRewards;
        }

        // Distribute rewards to delegators
        // TODO: remove the uint8 cast when PRs are merged
        uint256 delegatorCut = _graphStaking().getDelegationFeeCut(
            allocation.indexer,
            address(this),
            uint8(IGraphPayments.PaymentTypes.IndexingFee)
        );
        uint256 tokensDelegationRewards = tokensRewards.mulPPM(delegatorCut);
        if (tokensDelegationRewards > 0) {
            _graphToken().approve(address(_graphStaking()), tokensDelegationRewards);
            _graphStaking().addToDelegationPool(allocation.indexer, address(this), tokensDelegationRewards);
        }

        // Distribute rewards to indexer
        uint256 tokensIndexerRewards = tokensRewards - tokensDelegationRewards;
        address rewardsDestination = rewardsDestination[allocation.indexer];
        if (rewardsDestination == address(0)) {
            _graphToken().approve(address(_graphStaking()), tokensIndexerRewards);
            _graphStaking().stakeToProvision(allocation.indexer, address(this), tokensIndexerRewards);
        } else {
            _graphToken().transfer(rewardsDestination, tokensIndexerRewards);
        }

        emit IndexingRewardsCollected(
            allocation.indexer,
            allocationId,
            allocation.subgraphDeploymentId,
            tokensRewards,
            tokensIndexerRewards,
            tokensDelegationRewards,
            poi
        );

        return tokensRewards;
    }

    function _resizeAllocation(
        address _allocationId,
        uint256 _tokens,
        uint32 _delegationRatio
    ) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(_allocationId);

        // Exit early if the allocation size is the same
        if (_tokens == allocation.tokens) {
            revert AllocationManagerAllocationSameSize(_allocationId, _tokens);
        }

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
        uint256 accRewardsPending = accRewardsPerAllocatedToken - allocation.accRewardsPerAllocatedToken;

        // Update the allocation
        allocations[_allocationId].tokens = _tokens;
        allocations[_allocationId].accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        allocations[_allocationId].accRewardsPending += accRewardsPending;

        // Update total allocated tokens for the subgraph deployment
        // underflow: subgraphAllocatedTokens should at least be oldTokens so it can't underflow
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] += (_tokens - oldTokens);

        emit AllocationResized(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, _tokens, oldTokens);
        return allocations[_allocationId];
    }

    function _closeAllocation(address _allocationId) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(_allocationId);

        allocations.close(_allocationId);
        allocationProvisionTracker.release(allocation.indexer, allocation.tokens);

        // Take rewards snapshot to prevent other allos from counting tokens from this allo
        allocations.snapshotRewards(
            _allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] -
            allocation.tokens;

        emit AllocationClosed(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, allocation.tokens);
        return allocations[_allocationId];
    }

    function _setRewardsDestination(address _indexer, address _rewardsDestination) internal {
        rewardsDestination[_indexer] = _rewardsDestination;
        emit RewardsDestinationSet(_indexer, _rewardsDestination);
    }

    function _getAllocation(address _allocationId) internal view returns (Allocation.State memory) {
        return allocations.get(_allocationId);
    }

    function _getLegacyAllocation(address _allocationId) internal view returns (LegacyAllocation.State memory) {
        return legacyAllocations.get(_allocationId);
    }

    // -- Allocation Proof Verification --
    // Caller must prove that they own the private key for the allocationId address
    // The proof is an EIP712 signed message of (indexer,allocationId)
    function _verifyAllocationProof(address _indexer, address _allocationId, bytes memory _proof) internal view {
        bytes32 digest = _encodeAllocationProof(_indexer, _allocationId);
        address signer = ECDSA.recover(digest, _proof);
        if (signer != _allocationId) revert AllocationManagerInvalidAllocationProof(signer, _allocationId);
    }

    function _encodeAllocationProof(address _indexer, address _allocationId) internal view returns (bytes32) {
        return
            EIP712._hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_PROOF_TYPEHASH, _indexer, _allocationId)));
    }
}
