// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

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
 * @notice A helper contract implementing allocation lifecycle management.
 * Allows opening, resizing, and closing allocations, as well as collecting indexing rewards by presenting a Proof
 * of Indexing (POI).
 */
abstract contract AllocationManager is EIP712Upgradeable, GraphDirectory, AllocationManagerV1Storage {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;
    using LegacyAllocation for mapping(address => LegacyAllocation.State);
    using PPMMath for uint256;
    using TokenUtils for IGraphToken;

    ///@dev EIP712 typehash for allocation proof
    bytes32 private immutable EIP712_ALLOCATION_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    /**
     * @notice Emitted when an indexer creates an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     */
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
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
     */
    event IndexingRewardsCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards,
        bytes32 poi
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
     * @dev Emitted when an indexer closes an allocation
     * @param indexer The address of the indexer
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param tokens The amount of tokens allocated
     */
    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
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
     * @notice Emitted when an indexer sets a new indexing rewards destination
     * @param indexer The address of the indexer
     * @param rewardsDestination The address where indexing rewards should be sent
     */
    event RewardsDestinationSet(address indexed indexer, address indexed rewardsDestination);

    /**
     * @notice Emitted when the maximum POI staleness is updated
     * @param maxPOIStaleness The max POI staleness in seconds
     */
    event MaxPOIStalenessSet(uint256 maxPOIStaleness);

    /**
     * @notice Thrown when an allocation proof is invalid
     * Both `signer` and `allocationId` should match for a valid proof.
     * @param signer The address that signed the proof
     * @param allocationId The id of the allocation
     */
    error AllocationManagerInvalidAllocationProof(address signer, address allocationId);

    /**
     * @notice Thrown when attempting to create an allocation with a zero allocation id
     */
    error AllocationManagerInvalidZeroAllocationId();

    /**
     * @notice Thrown when attempting to collect indexing rewards on a closed allocationl
     * @param allocationId The id of the allocation
     */
    error AllocationManagerAllocationClosed(address allocationId);

    /**
     * @notice Thrown when attempting to resize an allocation with the same size
     * @param allocationId The id of the allocation
     * @param tokens The amount of tokens
     */
    error AllocationManagerAllocationSameSize(address allocationId, uint256 tokens);

    /**
     * @notice Initializes the contract and parent contracts
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AllocationManager_init(string memory _name, string memory _version) internal onlyInitializing {
        __EIP712_init(_name, _version);
        __AllocationManager_init_unchained(_name, _version);
    }

    /**
     * @notice Initializes the contract
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AllocationManager_init_unchained(
        string memory _name,
        string memory _version
    ) internal onlyInitializing {}

    /**
     * @notice Imports a legacy allocation id into the subgraph service
     * This is a governor only action that is required to prevent indexers from re-using allocation ids from the
     * legacy staking contract. It will revert with LegacyAllocationAlreadyMigrated if the allocation has already been migrated.
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     * @param _subgraphDeploymentId The id of the subgraph deployment
     */
    function _migrateLegacyAllocation(address _indexer, address _allocationId, bytes32 _subgraphDeploymentId) internal {
        legacyAllocations.migrate(_indexer, _allocationId, _subgraphDeploymentId);
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
    ) internal returns (Allocation.State memory) {
        require(_allocationId != address(0), AllocationManagerInvalidZeroAllocationId());

        _verifyAllocationProof(_indexer, _allocationId, _allocationProof);

        // Ensure allocation id is not reused
        // need to check both subgraph service (on allocations.create()) and legacy allocations
        legacyAllocations.revertIfExists(_allocationId);
        Allocation.State memory allocation = allocations.create(
            _indexer,
            _allocationId,
            _subgraphDeploymentId,
            _tokens,
            _graphRewardsManager().onSubgraphAllocationUpdate(_subgraphDeploymentId)
        );

        // Check that the indexer has enough tokens available
        // Note that the delegation ratio ensures overdelegation cannot be used
        allocationProvisionTracker.lock(_graphStaking(), _indexer, _tokens, _delegationRatio);

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] +
            allocation.tokens;

        emit AllocationCreated(_indexer, _allocationId, _subgraphDeploymentId, allocation.tokens);
        return allocation;
    }

    /**
     * @notice Present a POI to collect indexing rewards for an allocation
     * This function will mint indexing rewards using the {RewardsManager} and distribute them to the indexer and delegators.
     *
     * To qualify for indexing rewards:
     * - POI must be non-zero
     * - POI must not be stale, i.e: older than `maxPOIStaleness`
     * - allocation must not be altruistic (allocated tokens = 0)
     *
     * Note that indexers are required to periodically (at most every `maxPOIStaleness`) present POIs to collect rewards.
     * Rewards will not be issued to stale POIs, which means that indexers are advised to present a zero POI if they are
     * unable to present a valid one to prevent being locked out of future rewards.
     *
     * Emits a {IndexingRewardsCollected} event.
     *
     * @param _allocationId The id of the allocation to collect rewards for
     * @param _poi The POI being presented
     */
    function _collectIndexingRewards(
        address _allocationId,
        bytes32 _poi,
        uint32 _delegationRatio
    ) internal returns (uint256) {
        Allocation.State memory allocation = allocations.get(_allocationId);
        require(allocation.isOpen(), AllocationManagerAllocationClosed(_allocationId));

        // Mint indexing rewards if all conditions are met
        uint256 tokensRewards = (!allocation.isStale(maxPOIStaleness) &&
            !allocation.isAltruistic() &&
            _poi != bytes32(0))
            ? _graphRewardsManager().takeRewards(_allocationId)
            : 0;

        // ... but we still take a snapshot to ensure the rewards are not accumulated for the next valid POI
        allocations.snapshotRewards(
            _allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        allocations.presentPOI(_allocationId);

        // Any pending rewards should have been collected now
        allocations.clearPendingRewards(_allocationId);

        uint256 tokensIndexerRewards = 0;
        uint256 tokensDelegationRewards = 0;
        if (tokensRewards != 0) {
            // Distribute rewards to delegators
            uint256 delegatorCut = _graphStaking().getDelegationFeeCut(
                allocation.indexer,
                address(this),
                IGraphPayments.PaymentTypes.IndexingFee
            );
            tokensDelegationRewards = tokensRewards.mulPPM(delegatorCut);
            if (tokensDelegationRewards > 0) {
                _graphToken().approve(address(_graphStaking()), tokensDelegationRewards);
                _graphStaking().addToDelegationPool(allocation.indexer, address(this), tokensDelegationRewards);
            }

            // Distribute rewards to indexer
            tokensIndexerRewards = tokensRewards - tokensDelegationRewards;
            address rewardsDestination = rewardsDestination[allocation.indexer];
            if (rewardsDestination == address(0)) {
                _graphToken().approve(address(_graphStaking()), tokensIndexerRewards);
                _graphStaking().stakeToProvision(allocation.indexer, address(this), tokensIndexerRewards);
            } else {
                _graphToken().pushTokens(rewardsDestination, tokensIndexerRewards);
            }
        }

        emit IndexingRewardsCollected(
            allocation.indexer,
            _allocationId,
            allocation.subgraphDeploymentId,
            tokensRewards,
            tokensIndexerRewards,
            tokensDelegationRewards,
            _poi
        );

        // Check if the indexer is over-allocated and close the allocation if necessary
        if (!allocationProvisionTracker.check(_graphStaking(), allocation.indexer, _delegationRatio)) {
            _closeAllocation(_allocationId);
        }

        return tokensRewards;
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
    function _resizeAllocation(
        address _allocationId,
        uint256 _tokens,
        uint32 _delegationRatio
    ) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(_allocationId);
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
        allocations[_allocationId].tokens = _tokens;
        allocations[_allocationId].accRewardsPerAllocatedToken = accRewardsPerAllocatedToken;
        allocations[_allocationId].accRewardsPending += _graphRewardsManager().calcRewards(
            oldTokens,
            accRewardsPerAllocatedTokenPending
        );

        // Update total allocated tokens for the subgraph deployment
        if (_tokens > oldTokens) {
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] += (_tokens - oldTokens);
        } else {
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] -= (oldTokens - _tokens);
        }

        emit AllocationResized(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, _tokens, oldTokens);
        return allocations[_allocationId];
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
     */
    function _closeAllocation(address _allocationId) internal returns (Allocation.State memory) {
        Allocation.State memory allocation = allocations.get(_allocationId);

        // Take rewards snapshot to prevent other allos from counting tokens from this allo
        allocations.snapshotRewards(
            _allocationId,
            _graphRewardsManager().onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );

        allocations.close(_allocationId);
        allocationProvisionTracker.release(allocation.indexer, allocation.tokens);

        // Update total allocated tokens for the subgraph deployment
        subgraphAllocatedTokens[allocation.subgraphDeploymentId] =
            subgraphAllocatedTokens[allocation.subgraphDeploymentId] -
            allocation.tokens;

        emit AllocationClosed(allocation.indexer, _allocationId, allocation.subgraphDeploymentId, allocation.tokens);
        return allocations[_allocationId];
    }

    /**
     * @notice Sets the rewards destination for an indexer to receive indexing rewards
     * @dev Emits a {RewardsDestinationSet} event
     * @param _rewardsDestination The address where indexing rewards should be sent
     */
    function _setRewardsDestination(address _indexer, address _rewardsDestination) internal {
        rewardsDestination[_indexer] = _rewardsDestination;
        emit RewardsDestinationSet(_indexer, _rewardsDestination);
    }

    /**
     * @notice Sets the maximum amount of time, in seconds, allowed between presenting POIs to qualify for indexing rewards
     * @dev Emits a {MaxPOIStalenessSet} event
     * @param _maxPOIStaleness The max POI staleness in seconds
     */
    function _setMaxPOIStaleness(uint256 _maxPOIStaleness) internal {
        maxPOIStaleness = _maxPOIStaleness;
        emit MaxPOIStalenessSet(_maxPOIStaleness);
    }

    /**
     * @notice Gets the details of an allocation
     * @param _allocationId The id of the allocation
     */
    function _getAllocation(address _allocationId) internal view returns (Allocation.State memory) {
        return allocations.get(_allocationId);
    }

    /**
     * @notice Gets the details of a legacy allocation
     * @param _allocationId The id of the legacy allocation
     */
    function _getLegacyAllocation(address _allocationId) internal view returns (LegacyAllocation.State memory) {
        return legacyAllocations.get(_allocationId);
    }

    /**
     * @notice Verifies ownsership of an allocation id by verifying an EIP712 allocation proof
     * @dev Requirements:
     * - Signer must be the allocation id address
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     * @param _proof The EIP712 proof, an EIP712 signed message of (indexer,allocationId)
     */
    function _verifyAllocationProof(address _indexer, address _allocationId, bytes memory _proof) internal view {
        bytes32 digest = _encodeAllocationProof(_indexer, _allocationId);
        address signer = ECDSA.recover(digest, _proof);
        require(signer == _allocationId, AllocationManagerInvalidAllocationProof(signer, _allocationId));
    }

    /**
     * @notice Encodes the allocation proof for EIP712 signing
     * @param _indexer The address of the indexer
     * @param _allocationId The id of the allocation
     */
    function _encodeAllocationProof(address _indexer, address _allocationId) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_PROOF_TYPEHASH, _indexer, _allocationId)));
    }
}
