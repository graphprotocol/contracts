// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

import { GraphDirectory } from "@graphprotocol/horizon/contracts/utilities/GraphDirectory.sol";
import { AllocationManagerV1Storage } from "./AllocationManagerStorage.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { ProvisionTracker } from "@graphprotocol/horizon/contracts/data-service/libraries/ProvisionTracker.sol";
import { AllocationHandler } from "../libraries/AllocationHandler.sol";

/**
 * @title AllocationManager contract
 * @notice A helper contract implementing allocation lifecycle management.
 * Allows opening, resizing, and closing allocations, as well as collecting indexing rewards by presenting a Proof
 * of Indexing (POI).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AllocationManager is EIP712Upgradeable, GraphDirectory, AllocationManagerV1Storage {
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;
    using LegacyAllocation for mapping(address => LegacyAllocation.State);
    using PPMMath for uint256;
    using TokenUtils for IGraphToken;

    ///@dev EIP712 typehash for allocation id proof
    bytes32 private constant EIP712_ALLOCATION_ID_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    /**
     * @notice Initializes the contract and parent contracts
     * @param _name The name to use for EIP712 domain separation
     * @param _version The version to use for EIP712 domain separation
     */
    function __AllocationManager_init(string memory _name, string memory _version) internal onlyInitializing {
        __EIP712_init(_name, _version);
        __AllocationManager_init_unchained();
    }

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
        emit AllocationHandler.LegacyAllocationMigrated(_indexer, _allocationId, _subgraphDeploymentId);
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
        AllocationHandler.allocate(
            _allocations,
            _legacyAllocations,
            allocationProvisionTracker,
            _subgraphAllocatedTokens,
            AllocationHandler.AllocateParams({
                _allocationId: _allocationId,
                _allocationProof: _allocationProof,
                _encodeAllocationProof: _encodeAllocationProof(_indexer, _allocationId),
                _delegationRatio: _delegationRatio,
                _indexer: _indexer,
                _subgraphDeploymentId: _subgraphDeploymentId,
                _tokens: _tokens,
                currentEpoch: _graphEpochManager().currentEpoch(),
                graphRewardsManager: _graphRewardsManager(),
                graphStaking: _graphStaking()
            })
        );
    }

    /**
     * @notice Present a POI to collect indexing rewards for an allocation
     * This function will mint indexing rewards using the {RewardsManager} and distribute them to the indexer and delegators.
     *
     * Conditions to qualify for indexing rewards:
     * - POI must be non-zero
     * - POI must not be stale, i.e: older than `maxPOIStaleness`
     * - allocation must not be altruistic (allocated tokens = 0)
     * - allocation must be open for at least one epoch
     *
     * Note that indexers are required to periodically (at most every `maxPOIStaleness`) present POIs to collect rewards.
     * Rewards will not be issued to stale POIs, which means that indexers are advised to present a zero POI if they are
     * unable to present a valid one to prevent being locked out of future rewards.
     *
     * Note on allocation duration restriction: this is required to ensure that non protocol chains have a valid block number for
     * which to calculate POIs. EBO posts once per epoch typically at each epoch change, so we restrict rewards to allocations
     * that have gone through at least one epoch change.
     *
     * Emits a {IndexingRewardsCollected} event.
     *
     * @param _allocationId The id of the allocation to collect rewards for
     * @param _poi The POI being presented
     * @param _poiMetadata The metadata associated with the POI. The data and encoding format is for off-chain components to define, this function will only emit the value in an event as-is.
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _paymentsDestination The address where indexing rewards should be sent
     * @return The amount of tokens collected
     */
    function _presentPOI(
        address _allocationId,
        bytes32 _poi,
        bytes memory _poiMetadata,
        uint32 _delegationRatio,
        address _paymentsDestination
    ) internal returns (uint256) {
        return
            AllocationHandler.presentPOI(
                _allocations,
                allocationProvisionTracker,
                _subgraphAllocatedTokens,
                AllocationHandler.PresentParams({
                    maxPOIStaleness: maxPOIStaleness,
                    graphEpochManager: _graphEpochManager(),
                    graphStaking: _graphStaking(),
                    graphRewardsManager: _graphRewardsManager(),
                    graphToken: _graphToken(),
                    dataService: address(this),
                    _allocationId: _allocationId,
                    _poi: _poi,
                    _poiMetadata: _poiMetadata,
                    _delegationRatio: _delegationRatio,
                    _paymentsDestination: _paymentsDestination
                })
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
    function _resizeAllocation(address _allocationId, uint256 _tokens, uint32 _delegationRatio) internal {
        AllocationHandler.resizeAllocation(
            _allocations,
            allocationProvisionTracker,
            _subgraphAllocatedTokens,
            _graphStaking(),
            _graphRewardsManager(),
            _allocationId,
            _tokens,
            _delegationRatio
        );
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
        AllocationHandler.closeAllocation(
            _allocations,
            allocationProvisionTracker,
            _subgraphAllocatedTokens,
            _graphRewardsManager(),
            _allocationId,
            _forceClosed
        );
    }

    /**
     * @notice Sets the maximum amount of time, in seconds, allowed between presenting POIs to qualify for indexing rewards
     * @dev Emits a {MaxPOIStalenessSet} event
     * @param _maxPOIStaleness The max POI staleness in seconds
     */
    function _setMaxPOIStaleness(uint256 _maxPOIStaleness) internal {
        maxPOIStaleness = _maxPOIStaleness;
        emit AllocationHandler.MaxPOIStalenessSet(_maxPOIStaleness);
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
        return
            AllocationHandler.isOverAllocated(allocationProvisionTracker, _graphStaking(), _indexer, _delegationRatio);
    }
}
