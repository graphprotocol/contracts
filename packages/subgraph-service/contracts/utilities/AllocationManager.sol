// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { GraphDirectory } from "../data-service/GraphDirectory.sol";
import { AllocationManagerV1Storage } from "./AllocationManagerStorage.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { PPMMath } from "../data-service/libraries/PPMMath.sol";
import { ProvisionTracker } from "../data-service/libraries/ProvisionTracker.sol";

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

    event AllocationCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards
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

    error AllocationManagerInvalidAllocationProof(address signer, address allocationId);
    error AllocationManagerInvalidAllocationId();
    error AllocationManagerZeroTokensAllocation(address allocationId);
    error AllocationManagerAllocationClosed(address allocationId);
    error AllocationManagerAllocationSameSize(address allocationId, uint256 tokens);
    error AllocationManagerInvalidZeroPOI();

    constructor(string memory name, string memory version) EIP712(name, version) {}

    function _migrateLegacyAllocation(address indexer, address allocationId, bytes32 subgraphDeploymentId) internal {
        legacyAllocations.migrate(indexer, allocationId, subgraphDeploymentId);
        emit LegacyAllocationMigrated(indexer, allocationId, subgraphDeploymentId);
    }

    function _allocate(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        bytes memory allocationProof
    ) internal returns (Allocation.State memory) {
        if (allocationId == address(0)) revert AllocationManagerInvalidAllocationId();

        _verifyAllocationProof(indexer, allocationId, allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on create()) and legacy allocations
        legacyAllocations.revertIfExists(allocationId);
        Allocation.State memory allocation = allocations.create(
            indexer,
            allocationId,
            subgraphDeploymentId,
            tokens,
            // allos can be resized now, so we need to always take snapshot
            graphRewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentId)
        );

        // Check that the indexer has enough tokens available
        allocationProvisionTracker.lock(graphStaking, indexer, tokens);

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            allocation.tokens;

        emit AllocationCreated(indexer, allocationId, subgraphDeploymentId, allocation.tokens);
        return allocation;
    }

    // Update POI timestamp and take rewards snapshot even for 0 rewards
    // This ensures the rewards are actually skipped and not collected with the next valid POI
    function _collectPOIRewards(address allocationId, bytes32 poi) internal returns (Allocation.State memory) {
        if (poi == bytes32(0)) revert AllocationManagerInvalidZeroPOI();

        Allocation.State memory allocation = allocations.get(allocationId);

        // Mint indexing rewards, stale POIs get no rewards...
        uint256 timeSinceLastPOI = block.number - allocation.lastPOIPresentedAt;
        uint256 tokensRewards = timeSinceLastPOI <= maxPOIStaleness ? graphRewardsManager.takeRewards(allocationId) : 0;

        // ... but we still take a snapshot to ensure the rewards are not collected with the next valid POI
        allocations.snapshotRewards(
            allocationId,
            graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        allocations.presentPOI(allocationId);

        if (tokensRewards == 0) {
            return allocations[allocationId];
        }

        // Distribute rewards to delegators
        // TODO: remove the uint8 cast when PRs are merged
        uint256 delegatorCut = graphStaking.getDelegationCut(
            allocation.indexer,
            uint8(IGraphPayments.PaymentTypes.IndexingFee)
        );
        uint256 tokensDelegationRewards = tokensRewards.mulPPM(delegatorCut);
        graphToken.approve(address(graphStaking), tokensDelegationRewards);
        graphStaking.addToDelegationPool(allocation.indexer, tokensDelegationRewards);

        // Distribute rewards to indexer
        uint256 tokensIndexerRewards = tokensRewards - tokensDelegationRewards;
        address rewardsDestination = rewardsDestination[allocation.indexer];
        if (rewardsDestination == address(0)) {
            graphToken.approve(address(graphStaking), tokensIndexerRewards);
            graphStaking.stakeToProvision(allocation.indexer, address(this), tokensIndexerRewards);
        } else {
            graphToken.transfer(rewardsDestination, tokensIndexerRewards);
        }

        emit AllocationCollected(
            allocation.indexer,
            allocationId,
            allocation.subgraphDeploymentId,
            tokensRewards,
            tokensIndexerRewards,
            tokensDelegationRewards
        );

        return allocations[allocationId];
    }

    function _resizeAllocation(address allocationId, uint256 tokens) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(allocationId);

        // Exit early if the allocation size is the same
        if (tokens == allocation.tokens) {
            revert AllocationManagerAllocationSameSize(allocationId, tokens);
        }

        // Update provision tracker
        uint256 oldTokens = allocation.tokens;
        if (tokens > oldTokens) {
            allocationProvisionTracker.lock(graphStaking, allocation.indexer, tokens - oldTokens);
        } else {
            allocationProvisionTracker.release(allocation.indexer, oldTokens - tokens);
        }

        // Calculate rewards that have been accrued since the last snapshot but not yet issued
        uint256 accRewardsPerAllocatedToken = graphRewardsManager.onSubgraphAllocationUpdate(
            allocation.subgraphDeploymentId
        );
        uint256 accRewardsPending = accRewardsPerAllocatedToken - allocation.accRewardsPerAllocatedToken;

        // Update the allocation
        allocations[allocationId].tokens = tokens;
        allocations[allocationId].accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        allocations[allocationId].accRewardsPending = allocations[allocationId].accRewardsPending + accRewardsPending;

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            (tokens - oldTokens);

        emit AllocationResized(allocation.indexer, allocationId, allocation.subgraphDeploymentId, tokens, oldTokens);
        return allocations[allocationId];
    }

    function _closeAllocation(address allocationId) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(allocationId);

        allocations.close(allocationId);
        allocationProvisionTracker.release(allocation.indexer, allocation.tokens);

        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] -
            allocation.tokens;

        emit AllocationClosed(allocation.indexer, allocationId, allocation.subgraphDeploymentId, allocation.tokens);
        return allocations[allocationId];
    }

    function _getAllocation(address allocationId) internal view returns (Allocation.State memory) {
        return allocations.get(allocationId);
    }

    function _getLegacyAllocation(address allocationId) internal view returns (LegacyAllocation.State memory) {
        return legacyAllocations.get(allocationId);
    }

    // -- Allocation Proof Verification --
    // Caller must prove that they own the private key for the allocationId address
    // The proof is an EIP712 signed message of (indexer,allocationId)
    function _verifyAllocationProof(address indexer, address allocationId, bytes memory proof) internal view {
        bytes32 digest = _encodeAllocationProof(indexer, allocationId);
        address signer = ECDSA.recover(digest, proof);
        if (signer != allocationId) revert AllocationManagerInvalidAllocationProof(signer, allocationId);
    }

    function _encodeAllocationProof(address indexer, address allocationId) private view returns (bytes32) {
        return EIP712._hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_PROOF_TYPEHASH, indexer, allocationId)));
    }
}
