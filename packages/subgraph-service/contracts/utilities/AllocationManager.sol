// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { IAllocationManager } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol";
import { ILegacyAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/ILegacyAllocation.sol";

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
     * Mints indexing rewards using the {RewardsManager} and distributes them to the indexer and delegators.
     *
     * See {AllocationHandler-presentPOI} for detailed reward path documentation.
     *
     * Emits a {POIPresented} event.
     * Emits a {IndexingRewardsCollected} event.
     *
     * @param _allocationId The id of the allocation to collect rewards for
     * @param _poi The POI being presented
     * @param _poiMetadata Metadata associated with the POI, emitted as-is for off-chain components
     * @param _delegationRatio The delegation ratio to consider when locking tokens
     * @param _paymentsDestination The address where indexing rewards should be sent
     * @return rewardsCollected Indexing rewards collected
     * @return allocationForceClosed True if the allocation was force closed due to over-allocation
     */
    // solhint-disable-next-line function-max-lines
    function _presentPoi(
        address _allocationId,
        bytes32 _poi,
        bytes memory _poiMetadata,
        uint32 _delegationRatio,
        address _paymentsDestination
    ) internal returns (uint256, bool) {
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
            _delegationRatio,
            maxPOIStaleness
        );
    }

    /**
     * @notice Close an allocation
     * Does not require presenting a POI, use {_collectIndexingRewards} to present a POI and collect rewards
     * @dev Allocations are long-lived. All service payments, including indexing rewards, should be collected
     * periodically without closing. Allocations should only be closed when indexers want to reclaim tokens.
     *
     * ## Reward Handling on Close
     *
     * Uncollected rewards are reclaimed with CLOSE_ALLOCATION reason:
     * - If reclaim address configured: tokens minted to that address
     * - If no reclaim address: rewards are dropped (not minted anywhere)
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
        return
            AllocationHandler.isOverAllocated(allocationProvisionTracker, _graphStaking(), _indexer, _delegationRatio);
    }
}
