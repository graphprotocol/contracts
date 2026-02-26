// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IIndexingAgreement } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IIndexingAgreement.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";

import { AllocationHandler } from "../libraries/AllocationHandler.sol";
import { Directory } from "../utilities/Directory.sol";
import { Allocation } from "./Allocation.sol";
import { IndexingAgreementDecoder } from "./IndexingAgreementDecoder.sol";

/**
 * @title IndexingAgreement library
 * @author Edge & Node
 * @notice Manages indexing agreement lifecycle — acceptance, updates, cancellation, and fee collection.
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
        mapping(bytes16 => IIndexingAgreement.State) agreements;
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
     * @notice Emitted when an indexing agreement is canceled
     * @param indexer The address of the indexer
     * @param payer The address of the payer
     * @param agreementId The id of the agreement
     * @param canceledOnBehalfOf The address of the entity that canceled the agreement
     */
    event IndexingAgreementCanceled(
        address indexed indexer,
        address indexed payer,
        bytes16 indexed agreementId,
        address canceledOnBehalfOf
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
     * @notice Thrown when caller or proxy can not cancel an agreement
     * @param owner The address of the owner of the agreement
     * @param unauthorized The unauthorized caller
     */
    error IndexingAgreementNonCancelableBy(address owner, address unauthorized);

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

    /**
     * @notice Thrown when indexing agreement terms are invalid
     * @param tokensPerSecond The indexing agreement tokens per second
     * @param maxOngoingTokensPerSecond The RCA maximum tokens per second
     */
    error IndexingAgreementInvalidTerms(uint256 tokensPerSecond, uint256 maxOngoingTokensPerSecond);

    /* solhint-disable function-max-lines */
    /**
     * @notice Accept an indexing agreement.
     *
     * Requirements:
     * - Allocation must belong to the indexer and be open
     * - Agreement must be for this data service
     * - Agreement's subgraph deployment must match the allocation's subgraph deployment
     * - Agreement must not have been accepted before
     * - Allocation must not have an agreement already
     *
     * @dev signedRCA.rca.metadata is an encoding of {IndexingAgreement.AcceptIndexingAgreementMetadata}
     *
     * Emits {IndexingAgreementAccepted} event
     *
     * @param self The indexing agreement storage manager
     * @param allocations The mapping of allocation IDs to their states
     * @param allocationId The id of the allocation
     * @param signedRCA The signed Recurring Collection Agreement
     * @return The agreement ID assigned to the accepted indexing agreement
     */
    function accept(
        StorageManager storage self,
        mapping(address allocationId => IAllocation.State allocation) storage allocations,
        address allocationId,
        IRecurringCollector.SignedRCA calldata signedRCA
    ) external returns (bytes16) {
        IAllocation.State memory allocation = _requireValidAllocation(
            allocations,
            allocationId,
            signedRCA.rca.serviceProvider
        );

        require(
            signedRCA.rca.dataService == address(this),
            IndexingAgreementWrongDataService(address(this), signedRCA.rca.dataService)
        );

        AcceptIndexingAgreementMetadata memory metadata = IndexingAgreementDecoder.decodeRCAMetadata(
            signedRCA.rca.metadata
        );

        bytes16 agreementId = _directory().recurringCollector().generateAgreementId(
            signedRCA.rca.payer,
            signedRCA.rca.dataService,
            signedRCA.rca.serviceProvider,
            signedRCA.rca.deadline,
            signedRCA.rca.nonce
        );

        IIndexingAgreement.State storage agreement = self.agreements[agreementId];

        require(agreement.allocationId == address(0), IndexingAgreementAlreadyAccepted(agreementId));

        require(
            allocation.subgraphDeploymentId == metadata.subgraphDeploymentId,
            IndexingAgreementDeploymentIdMismatch(
                metadata.subgraphDeploymentId,
                allocationId,
                allocation.subgraphDeploymentId
            )
        );

        // Ensure that an allocation can only have one active indexing agreement
        require(
            self.allocationToActiveAgreementId[allocationId] == bytes16(0),
            AllocationAlreadyHasIndexingAgreement(allocationId)
        );
        self.allocationToActiveAgreementId[allocationId] = agreementId;

        agreement.version = metadata.version;
        agreement.allocationId = allocationId;

        require(
            metadata.version == IIndexingAgreement.IndexingAgreementVersion.V1,
            IndexingAgreementInvalidVersion(metadata.version)
        );
        _setTermsV1(self, agreementId, metadata.terms, signedRCA.rca.maxOngoingTokensPerSecond);

        emit IndexingAgreementAccepted(
            signedRCA.rca.serviceProvider,
            signedRCA.rca.payer,
            agreementId,
            allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );

        require(_directory().recurringCollector().accept(signedRCA) == agreementId, "internal: agreement ID mismatch");
        return agreementId;
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Update an indexing agreement.
     *
     * Requirements:
     * - Agreement must be active
     * - The indexer must be the service provider of the agreement
     *
     * @dev signedRCA.rcau.metadata is an encoding of {IndexingAgreement.UpdateIndexingAgreementMetadata}
     *
     * Emits {IndexingAgreementUpdated} event
     *
     * @param self The indexing agreement storage manager
     * @param indexer The indexer address
     * @param signedRCAU The signed Recurring Collection Agreement Update
     */
    function update(
        StorageManager storage self,
        address indexer,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) external {
        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, signedRCAU.rcau.agreementId);
        require(_isActive(wrapper), IndexingAgreementNotActive(signedRCAU.rcau.agreementId));
        require(
            wrapper.collectorAgreement.serviceProvider == indexer,
            IndexingAgreementNotAuthorized(signedRCAU.rcau.agreementId, indexer)
        );

        UpdateIndexingAgreementMetadata memory metadata = IndexingAgreementDecoder.decodeRCAUMetadata(
            signedRCAU.rcau.metadata
        );

        require(
            wrapper.agreement.version == IIndexingAgreement.IndexingAgreementVersion.V1,
            "internal: invalid version"
        );
        require(
            metadata.version == IIndexingAgreement.IndexingAgreementVersion.V1,
            IndexingAgreementInvalidVersion(metadata.version)
        );
        _setTermsV1(
            self,
            signedRCAU.rcau.agreementId,
            metadata.terms,
            wrapper.collectorAgreement.maxOngoingTokensPerSecond
        );

        emit IndexingAgreementUpdated({
            indexer: wrapper.collectorAgreement.serviceProvider,
            payer: wrapper.collectorAgreement.payer,
            agreementId: signedRCAU.rcau.agreementId,
            allocationId: wrapper.agreement.allocationId,
            version: metadata.version,
            versionTerms: metadata.terms
        });

        _directory().recurringCollector().update(signedRCAU);
    }

    /**
     * @notice Cancel an indexing agreement.
     *
     * @dev This function allows the indexer to cancel an indexing agreement.
     *
     * Requirements:
     * - Agreement must be active
     * - The indexer must be the service provider of the agreement
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param self The indexing agreement storage manager
     * @param indexer The indexer address
     * @param agreementId The id of the agreement to cancel
     */
    function cancel(StorageManager storage self, address indexer, bytes16 agreementId) external {
        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, agreementId);
        require(_isActive(wrapper), IndexingAgreementNotActive(agreementId));
        require(
            wrapper.collectorAgreement.serviceProvider == indexer,
            IndexingAgreementNonCancelableBy(wrapper.collectorAgreement.serviceProvider, indexer)
        );
        _cancel(
            self,
            agreementId,
            wrapper.agreement,
            wrapper.collectorAgreement,
            IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }

    /**
     * @notice Cancel an allocation's indexing agreement if it exists.
     *
     * @dev This function is to be called by the data service when an allocation is closed.
     *
     * Requirements:
     * - The allocation must have an active agreement
     * - Agreement must be active
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param self The indexing agreement storage manager
     * @param _allocationId The allocation ID
     * @param forceClosed Whether the allocation was force closed
     *
     */
    function onCloseAllocation(StorageManager storage self, address _allocationId, bool forceClosed) external {
        bytes16 agreementId = self.allocationToActiveAgreementId[_allocationId];
        if (agreementId == bytes16(0)) {
            return;
        }

        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, agreementId);
        if (!_isActive(wrapper)) {
            return;
        }

        _cancel(
            self,
            agreementId,
            wrapper.agreement,
            wrapper.collectorAgreement,
            forceClosed
                ? IRecurringCollector.CancelAgreementBy.ThirdParty
                : IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }

    /**
     * @notice Cancel an indexing agreement by the payer.
     *
     * @dev This function allows the payer to cancel an indexing agreement.
     *
     * Requirements:
     * - Agreement must be active
     * - The caller must be authorized to cancel the agreement in the collector on the payer's behalf
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param self The indexing agreement storage manager
     * @param agreementId The id of the agreement to cancel
     */
    function cancelByPayer(StorageManager storage self, bytes16 agreementId) external {
        IIndexingAgreement.AgreementWrapper memory wrapper = _get(self, agreementId);
        require(_isActive(wrapper), IndexingAgreementNotActive(agreementId));
        require(
            _directory().recurringCollector().isAuthorized(wrapper.collectorAgreement.payer, msg.sender),
            IndexingAgreementNonCancelableBy(wrapper.collectorAgreement.payer, msg.sender)
        );
        _cancel(
            self,
            agreementId,
            wrapper.agreement,
            wrapper.collectorAgreement,
            IRecurringCollector.CancelAgreementBy.Payer
        );
    }

    /* solhint-disable function-max-lines */
    /**
     * @notice Collect Indexing fees
     * @dev Uses the {RecurringCollector} to collect payment from Graph Horizon payments protocol.
     * Fees are distributed to service provider and delegators by {GraphPayments}
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
        // Get collection info from RecurringCollector (single source of truth for temporal logic)
        (bool isCollectable, uint256 collectionSeconds, ) = _directory().recurringCollector().getCollectionInfo(
            wrapper.collectorAgreement
        );
        require(_isValid(wrapper) && isCollectable, IndexingAgreementNotCollectable(params.agreementId));

        require(
            wrapper.agreement.version == IIndexingAgreement.IndexingAgreementVersion.V1,
            IndexingAgreementInvalidVersion(wrapper.agreement.version)
        );

        CollectIndexingFeeDataV1 memory data = IndexingAgreementDecoder.decodeCollectIndexingFeeDataV1(params.data);

        uint256 expectedTokens = (data.entities == 0 && data.poi == bytes32(0))
            ? 0
            : _tokensToCollect(self, params.agreementId, data.entities, collectionSeconds);

        // `tokensCollected` <= `expectedTokens` because the recurring collector will further narrow
        // down the tokens allowed, based on the RCA terms.
        uint256 tokensCollected = _directory().recurringCollector().collect(
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
     * @param maxOngoingTokensPerSecond The RCA maximum tokens per second limit for validation
     */
    function _setTermsV1(
        StorageManager storage _manager,
        bytes16 _agreementId,
        bytes memory _data,
        uint256 maxOngoingTokensPerSecond
    ) private {
        IndexingAgreementTermsV1 memory newTerms = IndexingAgreementDecoder.decodeIndexingAgreementTermsV1(_data);
        _validateTermsAgainstRCA(newTerms, maxOngoingTokensPerSecond);
        _manager.termsV1[_agreementId].tokensPerSecond = newTerms.tokensPerSecond;
        _manager.termsV1[_agreementId].tokensPerEntityPerSecond = newTerms.tokensPerEntityPerSecond;
    }

    /**
     * @notice Cancel an indexing agreement.
     *
     * @dev This function does the actual agreement cancelation.
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param _manager The indexing agreement storage manager
     * @param _agreementId The id of the agreement to cancel
     * @param _agreement The indexing agreement state
     * @param _collectorAgreement The collector agreement data
     * @param _cancelBy The entity that is canceling the agreement
     */
    function _cancel(
        StorageManager storage _manager,
        bytes16 _agreementId,
        IIndexingAgreement.State memory _agreement,
        IRecurringCollector.AgreementData memory _collectorAgreement,
        IRecurringCollector.CancelAgreementBy _cancelBy
    ) private {
        // Delete the allocation to active agreement link, so that the allocation
        // can be assigned a new indexing agreement in the future.
        delete _manager.allocationToActiveAgreementId[_agreement.allocationId];

        emit IndexingAgreementCanceled(
            _collectorAgreement.serviceProvider,
            _collectorAgreement.payer,
            _agreementId,
            _cancelBy == IRecurringCollector.CancelAgreementBy.Payer
                ? _collectorAgreement.payer
                : _collectorAgreement.serviceProvider
        );

        _directory().recurringCollector().cancel(_agreementId, _cancelBy);
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
     * @notice Calculate tokens to collect based on pre-validated duration
     * @param _manager The storage manager
     * @param _agreementId The agreement ID
     * @param _entities The number of entities indexed
     * @param _collectionSeconds Pre-calculated valid collection duration
     * @return The number of tokens to collect
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
     * @notice Checks if the agreement is active
     * Requirements:
     * - The indexing agreement is valid
     * - The underlying collector agreement has been accepted
     * @param wrapper The agreement wrapper containing the indexing agreement and collector agreement data
     * @return True if the agreement is active, false otherwise
     **/
    function _isActive(IIndexingAgreement.AgreementWrapper memory wrapper) private view returns (bool) {
        return _isValid(wrapper) && wrapper.collectorAgreement.state == IRecurringCollector.AgreementState.Accepted;
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
     * @notice Gets the Directory
     * @return The Directory contract
     */
    function _directory() private view returns (Directory) {
        return Directory(address(this));
    }

    /**
     * @notice Gets the indexing agreement wrapper for a given agreement ID.
     * @dev This function retrieves the indexing agreement wrapper containing the agreement state and collector agreement data.
     * @param self The indexing agreement storage manager
     * @param agreementId The id of the indexing agreement
     * @return The indexing agreement wrapper containing the agreement state and collector agreement data
     */
    function _get(
        StorageManager storage self,
        bytes16 agreementId
    ) private view returns (IIndexingAgreement.AgreementWrapper memory) {
        return
            IIndexingAgreement.AgreementWrapper({
                agreement: self.agreements[agreementId],
                collectorAgreement: _directory().recurringCollector().getAgreement(agreementId)
            });
    }

    /**
     * @notice Validates indexing agreement terms against RCA limits
     * @param terms The indexing agreement terms to validate
     * @param maxOngoingTokensPerSecond The RCA maximum tokens per second limit
     */
    function _validateTermsAgainstRCA(
        IndexingAgreementTermsV1 memory terms,
        uint256 maxOngoingTokensPerSecond
    ) private pure {
        require(
            // solhint-disable-next-line gas-strict-inequalities
            terms.tokensPerSecond <= maxOngoingTokensPerSecond,
            IndexingAgreementInvalidTerms(terms.tokensPerSecond, maxOngoingTokensPerSecond)
        );
    }
}
