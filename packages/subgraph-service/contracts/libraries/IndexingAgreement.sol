// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { SETTLED, IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";

import { AllocationHandler } from "../libraries/AllocationHandler.sol";
import { Allocation } from "./Allocation.sol";
import { IndexingAgreementDecoder } from "./IndexingAgreementDecoder.sol";

/**
 * @title IndexingAgreement library
 * @author Edge & Node
 * @notice Manages indexing agreement lifecycle: acceptance, updates, cancellation and fee collection.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library IndexingAgreement {
    using IndexingAgreement for StorageManager;
    using Allocation for IAllocation.State;
    using Allocation for mapping(address => IAllocation.State);

    /**
     * @notice Accept Indexing Agreement metadata
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param version The indexing agreement version
     * @param terms The indexing agreement terms
     */
    struct AcceptIndexingAgreementMetadata {
        bytes32 subgraphDeploymentId;
        IIndexingAgreement.IndexingAgreementVersion version;
        bytes terms;
    }

    /**
     * @notice Update Indexing Agreement metadata
     * @param version The indexing agreement version
     * @param terms The indexing agreement terms
     */
    struct UpdateIndexingAgreementMetadata {
        IIndexingAgreement.IndexingAgreementVersion version;
        bytes terms;
    }

    /**
     * @notice Indexing Agreement Terms (Version 1)
     * @param tokensPerSecond The amount of tokens per second
     * @param tokensPerEntityPerSecond The amount of tokens per entity per second
     */
    struct IndexingAgreementTermsV1 {
        uint256 tokensPerSecond;
        uint256 tokensPerEntityPerSecond;
    }

    /**
     * @notice Parameters for collecting indexing fees
     * @param indexer The address of the indexer
     * @param agreementId The ID of the indexing agreement
     * @param currentEpoch The current epoch
     * @param receiverDestination The address where the collected fees should be sent
     * @param data The encoded data containing the number of entities indexed, proof of indexing, and epoch
     * @param indexingFeesCut The indexing fees cut in PPM
     */
    struct CollectParams {
        address indexer;
        bytes16 agreementId;
        uint256 currentEpoch;
        address receiverDestination;
        bytes data;
        uint256 indexingFeesCut;
    }

    /**
     * @notice Nested data for collecting indexing fees V1.
     *
     * @param entities The number of entities
     * @param poi The proof of indexing (POI)
     * @param poiBlockNumber The block number of the POI
     * @param metadata Additional metadata associated with the collection
     * @param maxSlippage Max acceptable tokens to lose due to rate limiting, or type(uint256).max to ignore
     */
    struct CollectIndexingFeeDataV1 {
        uint256 entities;
        bytes32 poi;
        uint256 poiBlockNumber;
        bytes metadata;
        uint256 maxSlippage;
    }

    /**
     * @notice Storage manager for indexing agreements
     * @dev This struct holds the state of indexing agreements and their terms.
     * It is used to manage the lifecycle of indexing agreements in the subgraph service.
     * @param agreements Mapping of agreement IDs to their states
     * @param termsV1 Mapping of agreement IDs to their terms for version 1 agreements
     * @param allocationToActiveAgreementId Mapping of allocation IDs to their active agreement IDs
     * @custom:storage-location erc7201:graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement
     */
    struct StorageManager {
        mapping(bytes16 agreementId => IIndexingAgreement.State) agreements;
        mapping(bytes16 agreementId => IndexingAgreementTermsV1 data) termsV1;
        mapping(address allocationId => bytes16 agreementId) allocationToActiveAgreementId;
    }

    /**
     * @notice Storage location for the indexing agreement storage manager
     * @dev Equals keccak256(abi.encode(uint256(keccak256("graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 public constant INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION =
        0xb59b65b7215c7fb95ac34d2ad5aed7c775c8bc77ad936b1b43e17b95efc8e400;

    /**
     * @notice Emitted when an indexer collects indexing fees from a V1 agreement
     * @param indexer The address of the indexer
     * @param payer The address paying for the indexing fees
     * @param agreementId The id of the agreement
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param currentEpoch The current epoch
     * @param tokensCollected The amount of tokens collected
     * @param entities The number of entities indexed
     * @param poi The proof of indexing
     * @param poiBlockNumber The block number of the proof of indexing
     * @param metadata Additional metadata associated with the collection
     */
    event IndexingFeesCollectedV1(
        address indexed indexer,
        address indexed payer,
        bytes16 indexed agreementId,
        address allocationId,
        bytes32 subgraphDeploymentId,
        uint256 currentEpoch,
        uint256 tokensCollected,
        uint256 entities,
        bytes32 poi,
        uint256 poiBlockNumber,
        bytes metadata
    );

    /**
     * @notice Emitted when an indexing agreement is accepted
     * @param indexer The address of the indexer
     * @param payer The address of the payer
     * @param agreementId The id of the agreement
     * @param allocationId The id of the allocation
     * @param subgraphDeploymentId The id of the subgraph deployment
     * @param version The version of the indexing agreement
     * @param versionTerms The version data of the indexing agreement
     */
    event IndexingAgreementAccepted(
        address indexed indexer,
        address indexed payer,
        bytes16 indexed agreementId,
        address allocationId,
        bytes32 subgraphDeploymentId,
        IIndexingAgreement.IndexingAgreementVersion version,
        bytes versionTerms
    );

    /**
     * @notice Emitted when an indexing agreement is updated
     * @param indexer The address of the indexer
     * @param payer The address of the payer
     * @param agreementId The id of the agreement
     * @param allocationId The id of the allocation
     * @param version The version of the indexing agreement
     * @param versionTerms The version data of the indexing agreement
     */
    event IndexingAgreementUpdated(
        address indexed indexer,
        address indexed payer,
        bytes16 indexed agreementId,
        address allocationId,
        IIndexingAgreement.IndexingAgreementVersion version,
        bytes versionTerms
    );

    /**
     * @notice Thrown when trying to interact with an agreement with an invalid version
     * @param version The invalid version
     */
    error IndexingAgreementInvalidVersion(IIndexingAgreement.IndexingAgreementVersion version);

    /**
     * @notice Thrown when an agreement is not for the subgraph data service
     * @param expectedDataService The expected data service address
     * @param wrongDataService The wrong data service address
     */
    error IndexingAgreementWrongDataService(address expectedDataService, address wrongDataService);

    /**
     * @notice Thrown when the caller is not the collector that owns the agreement
     * @param agreementId The agreement ID
     * @param expectedCollector The collector that owns the agreement
     * @param actualCollector The caller
     */
    error IndexingAgreementCollectorMismatch(
        bytes16 agreementId,
        IRecurringCollector expectedCollector,
        IRecurringCollector actualCollector
    );

    /**
     * @notice Thrown when an agreement and the allocation correspond to different deployment IDs
     * @param agreementDeploymentId The agreement's deployment ID
     * @param allocationId The allocation ID
     * @param allocationDeploymentId The allocation's deployment ID
     */
    error IndexingAgreementDeploymentIdMismatch(
        bytes32 agreementDeploymentId,
        address allocationId,
        bytes32 allocationDeploymentId
    );

    /**
     * @notice Thrown when the agreement is already accepted
     * @param agreementId The agreement ID
     */
    error IndexingAgreementAlreadyAccepted(bytes16 agreementId);

    /**
     * @notice Thrown when an allocation already has an active agreement
     * @param allocationId The allocation ID
     */
    error AllocationAlreadyHasIndexingAgreement(address allocationId);

    /**
     * @notice Emitted when an allocation is unbound from an indexing agreement
     * @param agreementId The agreement ID
     * @param allocationId The allocation ID that was unbound
     */
    event IndexingAgreementAllocationUnbound(bytes16 indexed agreementId, address indexed allocationId);

    /**
     * @notice Thrown when the agreement is not active
     * @param agreementId The agreement ID
     */
    error IndexingAgreementNotActive(bytes16 agreementId);

    /**
     * @notice Thrown when the agreement is not collectable
     * @param agreementId The agreement ID
     */
    error IndexingAgreementNotCollectable(bytes16 agreementId);

    /**
     * @notice Thrown when trying to interact with an agreement not owned by the indexer
     * @param agreementId The agreement ID
     * @param unauthorizedIndexer The unauthorized indexer
     */
    error IndexingAgreementNotAuthorized(bytes16 agreementId, address unauthorizedIndexer);

    /* solhint-disable function-max-lines */
    /**
     * @notice Handle acceptance of an agreement (initial or update).
     * @dev Called by SubgraphService.acceptAgreement for both initial accepts and updates.
     * On initial accept (collector not yet set): validates allocation binding, deployment
     * match against payer-signed metadata, stores collector and deployment ID.
     * On update (collector already set): validates collector identity, optionally rebinds
     * allocation, updates terms.
     *
     * Requirements:
     * - Initial: allocation must belong to the indexer and be open, deployment must match
     *   metadata, agreement must not have been accepted before, allocation must not be bound
     * - Update: caller must be the collector that owns the agreement, version must be V1
     * - If rebinding (extraData contains new allocationId): new allocation must be open,
     *   owned by indexer, on the same deployment, and not already bound
     *
     * Emits {IndexingAgreementAccepted} on initial accept
     * Emits {IndexingAgreementUpdated} on update
     *
     * @param self The indexing agreement storage manager
     * @param allocations The mapping of allocation IDs to their states
     * @param agreementId The ID of the agreement being accepted
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider (indexer)
     * @param metadata The agreement metadata (encoded Accept or Update metadata)
     * @param extraData Encoded allocationId — required for initial, optional for update
     * @param collector The collector contract address (msg.sender from the callback)
     */
    function onAcceptCallback(
        StorageManager storage self,
        mapping(address allocationId => IAllocation.State allocation) storage allocations,
        bytes16 agreementId,
        address payer,
        address serviceProvider,
        bytes calldata metadata,
        bytes calldata extraData,
        IRecurringCollector collector
    ) external {
        IIndexingAgreement.State storage agreement = self.agreements[agreementId];
        bool isInitial = address(agreement.collector) == address(0);

        // ── 1. Collector identity ──
        if (isInitial) agreement.collector = collector;
        else
            require(
                address(agreement.collector) == address(collector),
                IndexingAgreementCollectorMismatch(agreementId, agreement.collector, collector)
            );

        // ── 2. Decode metadata (different structs, same outputs) ──
        IIndexingAgreement.IndexingAgreementVersion version;
        bytes memory terms;

        if (isInitial) {
            require(agreement.allocationId == address(0), IndexingAgreementAlreadyAccepted(agreementId));

            AcceptIndexingAgreementMetadata memory meta = IndexingAgreementDecoder.decodeRCAMetadata(metadata);
            version = meta.version;
            terms = meta.terms;

            agreement.subgraphDeploymentId = meta.subgraphDeploymentId;
        } else {
            UpdateIndexingAgreementMetadata memory meta = IndexingAgreementDecoder.decodeRCAUMetadata(metadata);
            version = meta.version;
            terms = meta.terms;
        }

        // ── 3. Allocation binding ──
        _bindAllocation(self, allocations, agreement, agreementId, serviceProvider, extraData);

        // ── 5. Version + terms ──
        require(version == IIndexingAgreement.IndexingAgreementVersion.V1, IndexingAgreementInvalidVersion(version));
        agreement.version = version;
        _setTermsV1(self, agreementId, terms);

        // ── 6. Events ──
        if (isInitial)
            emit IndexingAgreementAccepted(
                serviceProvider,
                payer,
                agreementId,
                agreement.allocationId,
                agreement.subgraphDeploymentId,
                version,
                terms
            );
        else
            emit IndexingAgreementUpdated({
                indexer: serviceProvider,
                payer: payer,
                agreementId: agreementId,
                allocationId: agreement.allocationId,
                version: version,
                versionTerms: terms
            });
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Handle an allocation's indexing agreement when the allocation is closed.
     *
     * @dev Called by the data service when an allocation is closed.
     * When `_blockIfActive` is true, reverts if the agreement is not SETTLED.
     * When false, clears the mapping regardless of settlement state.
     *
     * DoS note: the external call to `getAgreementVersionAt` is unguarded. If the
     * collector reverts (broken upgrade, corrupt storage), allocation closure is blocked.
     * Mitigations: (1) governor can disable `blockClosingAllocationWithActiveAgreement`,
     * (2) indexer can self-cancel via collector to set SETTLED then close,
     * (3) `getAgreementVersionAt` is a view with no pause guard, so collector pause
     * does not block it.
     *
     * Escape hatch: BY_PROVIDER cancel sets SETTLED immediately, so the indexer can
     * always self-cancel then close.
     * Clears both sides of the bidirectional mapping atomically.
     *
     * @param self The indexing agreement storage manager
     * @param _allocationId The allocation ID
     * @param _blockIfActive Whether to revert if the agreement is not settled
     */
    function onCloseAllocation(StorageManager storage self, address _allocationId, bool _blockIfActive) external {
        bytes16 agreementId = self.allocationToActiveAgreementId[_allocationId];
        if (agreementId == bytes16(0)) return;

        if (_blockIfActive) {
            // Check SETTLED on-demand via the collector
            IAgreementCollector.AgreementVersion memory version = IAgreementCollector(
                self.agreements[agreementId].collector
            ).getAgreementVersionAt(agreementId, 0);

            if (version.state & SETTLED == 0)
                revert ISubgraphService.SubgraphServiceAllocationHasActiveAgreement(_allocationId, agreementId);
        }

        // Clear both sides of the bidirectional mapping atomically
        delete self.allocationToActiveAgreementId[_allocationId];
        self.agreements[agreementId].allocationId = address(0);
        emit IndexingAgreementAllocationUnbound(agreementId, _allocationId);
    }

    /* solhint-disable function-max-lines */
    /**
     * @notice Collect indexing fees for an agreement.
     * @dev Computes a requested token amount from indexing agreement terms
     * (`collectionSeconds * (tokensPerSecond + tokensPerEntityPerSecond * entities)`) and passes
     * it to the collector, which caps it against the payer's limits. The actual payout
     * is the minimum of the two. Every POI submitted is disputable — no exception for zero POI.
     *
     * Requirements:
     * - Allocation must be open
     * - Agreement must be active
     * - Agreement must be of version V1
     * - The data must be encoded as per {IndexingAgreementDecoder.decodeCollectIndexingFeeDataV1}
     *
     * Emits a {IndexingFeesCollectedV1} event.
     *
     * @param self The indexing agreement storage manager
     * @param allocations The mapping of allocation IDs to their states
     * @param params The parameters for collecting indexing fees
     * @return The address of the service provider that collected the fees
     * @return The amount of fees collected
     */
    function collect(
        StorageManager storage self,
        mapping(address allocationId => IAllocation.State allocation) storage allocations,
        CollectParams calldata params
    ) external returns (address, uint256) {
        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, params.agreementId);
        IAllocation.State memory allocation = _requireValidAllocation(
            allocations,
            wrapper.agreement.allocationId,
            wrapper.collectorAgreement.serviceProvider
        );
        require(
            allocation.indexer == params.indexer,
            IndexingAgreementNotAuthorized(params.agreementId, params.indexer)
        );
        IRecurringCollector rc = wrapper.agreement.collector;

        // Collection info comes from the collector (single source of truth for temporal logic)
        require(
            _isValid(wrapper) && wrapper.collectorAgreement.isCollectable,
            IndexingAgreementNotCollectable(params.agreementId)
        );

        require(
            wrapper.agreement.version == IIndexingAgreement.IndexingAgreementVersion.V1,
            IndexingAgreementInvalidVersion(wrapper.agreement.version)
        );

        CollectIndexingFeeDataV1 memory data = IndexingAgreementDecoder.decodeCollectIndexingFeeDataV1(params.data);

        uint256 expectedTokens = _tokensToCollect(
            self,
            params.agreementId,
            data.entities,
            wrapper.collectorAgreement.collectionSeconds
        );

        // Trust boundary: the collector is owner-authorized and controls the actual token
        // transfer (via PaymentsEscrow.collect). It is trusted for both the amount moved and
        // the return value. A return-value sanity check would not limit a buggy collector's
        // ability to move tokens, only catch a misreported return value. The downstream effect
        // of an inflated return is over-locking indexer stake (tokensCollected * stakeToFeesRatio).
        // Mitigation is governance-level: only the contract owner can authorize collectors.
        uint256 tokensCollected = rc.collect(
            IGraphPayments.PaymentTypes.IndexingFee,
            abi.encode(
                IRecurringCollector.CollectParams({
                    agreementId: params.agreementId,
                    collectionId: bytes32(uint256(uint160(wrapper.agreement.allocationId))),
                    tokens: expectedTokens,
                    dataServiceCut: params.indexingFeesCut,
                    receiverDestination: params.receiverDestination,
                    maxSlippage: data.maxSlippage
                })
            )
        );

        emit IndexingFeesCollectedV1(
            wrapper.collectorAgreement.serviceProvider,
            wrapper.collectorAgreement.payer,
            params.agreementId,
            wrapper.agreement.allocationId,
            allocation.subgraphDeploymentId,
            params.currentEpoch,
            tokensCollected,
            data.entities,
            data.poi,
            data.poiBlockNumber,
            data.metadata
        );

        return (wrapper.collectorAgreement.serviceProvider, tokensCollected);
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Get the indexing agreement for a given agreement ID.
     *
     * @param self The indexing agreement storage manager
     * @param agreementId The id of the indexing agreement
     * @return The indexing agreement wrapper containing the agreement state and collector agreement data
     */
    function get(
        StorageManager storage self,
        bytes16 agreementId
    ) external view returns (IIndexingAgreement.AgreementWrapper memory) {
        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, agreementId);
        require(wrapper.collectorAgreement.dataService == address(this), IndexingAgreementNotActive(agreementId));

        return wrapper;
    }

    /**
     * @notice Get the storage manager for indexing agreements.
     * @dev This function retrieves the storage manager for indexing agreements.
     * @return m The storage manager for indexing agreements
     */
    function _getStorageManager() internal pure returns (StorageManager storage m) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            m.slot := INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION
        }
    }

    /**
     * @notice Set the terms for an indexing agreement of version V1.
     * @dev This function updates the terms of an indexing agreement in the storage manager.
     * @param _manager The indexing agreement storage manager
     * @param _agreementId The id of the agreement to update
     * @param _data The encoded terms data
     */
    function _setTermsV1(StorageManager storage _manager, bytes16 _agreementId, bytes memory _data) private {
        IndexingAgreementTermsV1 memory newTerms = IndexingAgreementDecoder.decodeIndexingAgreementTermsV1(_data);
        _manager.termsV1[_agreementId].tokensPerSecond = newTerms.tokensPerSecond;
        _manager.termsV1[_agreementId].tokensPerEntityPerSecond = newTerms.tokensPerEntityPerSecond;
    }

    /**
     * @notice Requires that the allocation is valid and owned by the indexer.
     *
     * Requirements:
     * - Allocation must belong to the indexer
     * - Allocation must be open
     *
     * @param _allocations The mapping of allocation IDs to their states
     * @param _allocationId The id of the allocation
     * @param _indexer The address of the indexer
     * @return The allocation state
     */
    function _requireValidAllocation(
        mapping(address => IAllocation.State) storage _allocations,
        address _allocationId,
        address _indexer
    ) private view returns (IAllocation.State memory) {
        IAllocation.State memory allocation = _allocations.get(_allocationId);
        require(
            allocation.indexer == _indexer,
            ISubgraphService.SubgraphServiceAllocationNotAuthorized(_indexer, _allocationId)
        );
        require(allocation.isOpen(), AllocationHandler.AllocationHandlerAllocationClosed(_allocationId));

        return allocation;
    }

    /**
     * @notice Bind or rebind an agreement to an allocation.
     * @dev If `_extraData` contains a new allocationId, validates it and updates
     * the bidirectional mapping. After binding, requires the agreement has a valid,
     * open allocation owned by the indexer.
     *
     * @param _manager The storage manager
     * @param _allocations The allocation state mapping
     * @param _agreement The agreement state (storage ref)
     * @param _agreementId The agreement ID
     * @param _serviceProvider The indexer address
     * @param _extraData Encoded allocationId — required for initial, optional for update
     */
    function _bindAllocation(
        StorageManager storage _manager,
        mapping(address => IAllocation.State) storage _allocations,
        IIndexingAgreement.State storage _agreement,
        bytes16 _agreementId,
        address _serviceProvider,
        bytes calldata _extraData
    ) private {
        if (0 < _extraData.length) {
            address newAllocationId = abi.decode(_extraData, (address));
            address oldAllocationId = _agreement.allocationId;

            if (newAllocationId != oldAllocationId) {
                IAllocation.State memory newAllocation = _requireValidAllocation(
                    _allocations,
                    newAllocationId,
                    _serviceProvider
                );

                require(
                    newAllocation.subgraphDeploymentId == _agreement.subgraphDeploymentId,
                    IndexingAgreementDeploymentIdMismatch(
                        _agreement.subgraphDeploymentId,
                        newAllocationId,
                        newAllocation.subgraphDeploymentId
                    )
                );

                if (oldAllocationId != address(0)) {
                    delete _manager.allocationToActiveAgreementId[oldAllocationId];
                    emit IndexingAgreementAllocationUnbound(_agreementId, oldAllocationId);
                }

                require(
                    _manager.allocationToActiveAgreementId[newAllocationId] == bytes16(0),
                    AllocationAlreadyHasIndexingAgreement(newAllocationId)
                );

                _manager.allocationToActiveAgreementId[newAllocationId] = _agreementId;
                _agreement.allocationId = newAllocationId;
            }
        }

        require(_agreement.allocationId != address(0), IndexingAgreementNotActive(_agreementId));
        _requireValidAllocation(_allocations, _agreement.allocationId, _serviceProvider);
    }

    /**
     * @notice Calculate the data service's requested token amount for a collection.
     * @dev This is an upper bound based on indexing agreement terms, not a guaranteed payout.
     * The collector further caps the actual payout against the payer's limits.
     * @param _manager The storage manager
     * @param _agreementId The agreement ID
     * @param _entities The number of entities indexed
     * @param _collectionSeconds Collection duration, already capped at maxSecondsPerCollection
     * @return The requested token amount (may be narrowed by the collector)
     */
    function _tokensToCollect(
        StorageManager storage _manager,
        bytes16 _agreementId,
        uint256 _entities,
        uint256 _collectionSeconds
    ) private view returns (uint256) {
        IndexingAgreementTermsV1 memory termsV1 = _manager.termsV1[_agreementId];
        return _collectionSeconds * (termsV1.tokensPerSecond + termsV1.tokensPerEntityPerSecond * _entities);
    }

    /**
     * @notice Checks if the agreement is valid
     * Requirements:
     * - The underlying collector agreement's data service is this contract
     * - The indexing agreement has been accepted and has a valid allocation ID
     * @param wrapper The agreement wrapper containing the indexing agreement and collector agreement data
     * @return True if the agreement is valid, false otherwise
     **/
    function _isValid(IIndexingAgreement.AgreementWrapper memory wrapper) private view returns (bool) {
        return wrapper.collectorAgreement.dataService == address(this) && wrapper.agreement.allocationId != address(0);
    }

    /**
     * @notice Gets the indexing agreement wrapper for a given agreement ID.
     * @dev This function retrieves the indexing agreement wrapper containing the agreement state and collector agreement data.
     * @param self The indexing agreement storage manager
     * @param agreementId The id of the indexing agreement
     * @return wrapper The indexing agreement wrapper containing the agreement state and collector agreement data
     */
    function _get(
        StorageManager storage self,
        bytes16 agreementId
    ) private view returns (IIndexingAgreement.AgreementWrapper memory wrapper) {
        wrapper.agreement = self.agreements[agreementId];
        if (address(wrapper.agreement.collector) != address(0)) {
            wrapper.collectorAgreement = wrapper.agreement.collector.getAgreementData(agreementId);
        }
    }
}
