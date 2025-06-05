// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { GraphDirectory } from "@graphprotocol/horizon/contracts/utilities/GraphDirectory.sol";

import { SubgraphService } from "../SubgraphService.sol";
import { Directory } from "../utilities/Directory.sol";
import { Allocation } from "./Allocation.sol";
import { SubgraphServiceLib } from "./SubgraphServiceLib.sol";
import { Decoder } from "./Decoder.sol";

library IndexingAgreement {
    using IndexingAgreement for StorageManager;
    using Allocation for mapping(address => Allocation.State);
    using SubgraphServiceLib for mapping(address => Allocation.State);

    /// @notice Versions of Indexing Agreement Metadata
    enum IndexingAgreementVersion {
        V1
    }

    /**
     * @notice Indexer Agreement Data
     * @param allocationId The allocation ID
     * @param version The indexing agreement version
     */
    struct State {
        address allocationId;
        IndexingAgreementVersion version;
    }

    struct AgreementWrapper {
        State agreement;
        IRecurringCollector.AgreementData collectorAgreement;
    }

    /**
     * @notice Accept Indexing Agreement metadata
     * @param subgraphDeploymentId The subgraph deployment ID
     * @param version The indexing agreement version
     * @param terms The indexing agreement terms
     */
    struct AcceptIndexingAgreementMetadata {
        bytes32 subgraphDeploymentId;
        IndexingAgreementVersion version;
        bytes terms;
    }

    /**
     * @notice Update Indexing Agreement metadata
     * @param version The indexing agreement version
     * @param terms The indexing agreement terms
     */
    struct UpdateIndexingAgreementMetadata {
        IndexingAgreementVersion version;
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

    struct CollectParams {
        bytes16 agreementId;
        uint256 currentEpoch;
        bytes data;
    }

    /// @custom:storage-location erc7201:graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement
    struct StorageManager {
        mapping(bytes16 => State) agreements;
        mapping(bytes16 agreementId => IndexingAgreementTermsV1 data) termsV1;
        mapping(address allocationId => bytes16 agreementId) allocationToActiveAgreementId;
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION =
        0xb59b65b7215c7fb95ac34d2ad5aed7c775c8bc77ad936b1b43e17b95efc8e400;

    /**
     * @notice Emitted when an indexer collects indexing fees from a V1 agreement
     * @param indexer The address of the indexer
     * @param payer The address paying for the indexing fees
     * @param agreementId The id of the agreement
     * @param currentEpoch The current epoch
     * @param tokensCollected The amount of tokens collected
     * @param entities The number of entities indexed
     * @param poi The proof of indexing
     * @param poiEpoch The epoch of the proof of indexing
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
        uint256 poiEpoch
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
        IndexingAgreementVersion version,
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
        IndexingAgreementVersion version,
        bytes versionTerms
    );

    /**
     * @notice Thrown when trying to interact with an agreement with an invalid version
     * @param version The invalid version
     */
    error InvalidIndexingAgreementVersion(IndexingAgreementVersion version);

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
     * @notice Thrown when trying to interact with an agreement not owned by the indexer
     * @param agreementId The agreement ID
     * @param unauthorizedIndexer The unauthorized indexer
     */
    error IndexingAgreementNotAuthorized(bytes16 agreementId, address unauthorizedIndexer);

    function accept(
        StorageManager storage self,
        mapping(address allocationId => Allocation.State allocation) storage allocations,
        address allocationId,
        IRecurringCollector.SignedRCA calldata signedRCA
    ) external {
        Allocation.State memory allocation = allocations.requireValidAllocation(
            allocationId,
            signedRCA.rca.serviceProvider
        );

        require(
            signedRCA.rca.dataService == address(this),
            IndexingAgreementWrongDataService(address(this), signedRCA.rca.dataService)
        );

        AcceptIndexingAgreementMetadata memory metadata = Decoder.decodeRCAMetadata(signedRCA.rca.metadata);

        State storage agreement = self.agreements[signedRCA.rca.agreementId];

        require(agreement.allocationId == address(0), IndexingAgreementAlreadyAccepted(signedRCA.rca.agreementId));

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
        self.allocationToActiveAgreementId[allocationId] = signedRCA.rca.agreementId;

        agreement.version = metadata.version;
        agreement.allocationId = allocationId;

        require(metadata.version == IndexingAgreementVersion.V1, InvalidIndexingAgreementVersion(metadata.version));
        _setTermsV1(self, signedRCA.rca.agreementId, metadata.terms);

        emit IndexingAgreementAccepted(
            signedRCA.rca.serviceProvider,
            signedRCA.rca.payer,
            signedRCA.rca.agreementId,
            allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );

        _directory().recurringCollector().accept(signedRCA);
    }

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
     * @param self The indexing agreement manager storage
     * @param indexer The indexer address
     * @param signedRCAU The signed Recurring Collection Agreement Update
     */
    function update(
        StorageManager storage self,
        address indexer,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) external {
        AgreementWrapper memory wrapper = _get(self, signedRCAU.rcau.agreementId);
        require(_isActive(wrapper), IndexingAgreementNotActive(signedRCAU.rcau.agreementId));
        require(
            wrapper.collectorAgreement.serviceProvider == indexer,
            IndexingAgreementNotAuthorized(signedRCAU.rcau.agreementId, indexer)
        );

        UpdateIndexingAgreementMetadata memory metadata = Decoder.decodeRCAUMetadata(signedRCAU.rcau.metadata);

        wrapper.agreement.version = metadata.version;

        require(metadata.version == IndexingAgreementVersion.V1, InvalidIndexingAgreementVersion(metadata.version));
        _setTermsV1(self, signedRCAU.rcau.agreementId, metadata.terms);

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
     * Requirements:
     * - Agreement must be active
     * - The indexer must be the service provider of the agreement
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param self The indexing agreement manager storage
     * @param indexer The indexer address
     * @param agreementId The id of the agreement to cancel
     */
    function cancel(StorageManager storage self, address indexer, bytes16 agreementId) external {
        AgreementWrapper memory wrapper = _get(self, agreementId);
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

    function cancelForAllocation(StorageManager storage self, address _allocationId) external {
        bytes16 agreementId = self.allocationToActiveAgreementId[_allocationId];
        if (agreementId == bytes16(0)) {
            return;
        }

        AgreementWrapper memory wrapper = _get(self, agreementId);
        if (!_isActive(wrapper)) {
            return;
        }

        _cancel(
            self,
            agreementId,
            wrapper.agreement,
            wrapper.collectorAgreement,
            IRecurringCollector.CancelAgreementBy.ServiceProvider
        );
    }

    function cancelByPayer(StorageManager storage self, bytes16 agreementId) external {
        AgreementWrapper memory wrapper = _get(self, agreementId);
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

    function collect(
        StorageManager storage self,
        mapping(address allocationId => Allocation.State allocation) storage allocations,
        CollectParams memory params
    ) external returns (address, uint256) {
        AgreementWrapper memory wrapper = _get(self, params.agreementId);
        Allocation.State memory allocation = allocations.requireValidAllocation(
            wrapper.agreement.allocationId,
            wrapper.collectorAgreement.serviceProvider
        );
        require(_isActive(wrapper), IndexingAgreementNotActive(params.agreementId));

        require(
            wrapper.agreement.version == IndexingAgreementVersion.V1,
            InvalidIndexingAgreementVersion(wrapper.agreement.version)
        );

        (uint256 entities, bytes32 poi, uint256 poiEpoch) = Decoder.decodeCollectIndexingFeeDataV1(params.data);

        uint256 expectedTokens = (entities == 0 && poi == bytes32(0))
            ? 0
            : _tokensToCollect(self, params.agreementId, wrapper.collectorAgreement, entities);

        uint256 tokensCollected = _directory().recurringCollector().collect(
            IGraphPayments.PaymentTypes.IndexingFee,
            abi.encode(
                IRecurringCollector.CollectParams({
                    agreementId: params.agreementId,
                    collectionId: bytes32(uint256(uint160(wrapper.agreement.allocationId))),
                    tokens: expectedTokens,
                    dataServiceCut: 0
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
            entities,
            poi,
            poiEpoch
        );

        return (wrapper.collectorAgreement.serviceProvider, tokensCollected);
    }

    function get(StorageManager storage self, bytes16 agreementId) external view returns (AgreementWrapper memory) {
        AgreementWrapper memory wrapper = _get(self, agreementId);
        require(wrapper.collectorAgreement.dataService == address(this), IndexingAgreementNotActive(agreementId));

        return wrapper;
    }

    function _getStorageManager() internal pure returns (StorageManager storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION
        }
    }

    function _setTermsV1(StorageManager storage _manager, bytes16 _agreementId, bytes memory _data) private {
        IndexingAgreementTermsV1 memory newTerms = Decoder.decodeIndexingAgreementTermsV1(_data);
        _manager.termsV1[_agreementId].tokensPerSecond = newTerms.tokensPerSecond;
        _manager.termsV1[_agreementId].tokensPerEntityPerSecond = newTerms.tokensPerEntityPerSecond;
    }

    function _cancel(
        StorageManager storage _manager,
        bytes16 _agreementId,
        State memory _agreement,
        IRecurringCollector.AgreementData memory _collectorAgreement,
        IRecurringCollector.CancelAgreementBy _cancelBy
    ) private {
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

    function _tokensToCollect(
        StorageManager storage _manager,
        bytes16 _agreementId,
        IRecurringCollector.AgreementData memory _agreement,
        uint256 _entities
    ) private view returns (uint256) {
        IndexingAgreementTermsV1 memory termsV1 = _manager.termsV1[_agreementId];

        uint256 collectionSeconds = block.timestamp;
        collectionSeconds -= _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;

        return collectionSeconds * (termsV1.tokensPerSecond + termsV1.tokensPerEntityPerSecond * _entities);
    }

    /**
     * @notice Checks if the agreement is active
     * Requirements:
     * - The underlying collector agreement has been accepted
     * - The underlying collector agreement's data service is this contract
     * - The indexing agreement has been accepted and has a valid allocation ID
     **/
    function _isActive(AgreementWrapper memory wrapper) private view returns (bool) {
        return
            wrapper.collectorAgreement.dataService == address(this) &&
            wrapper.collectorAgreement.state == IRecurringCollector.AgreementState.Accepted &&
            wrapper.agreement.allocationId != address(0);
    }

    function _directory() private view returns (Directory) {
        return Directory(address(this));
    }

    function _graphDirectory() private view returns (GraphDirectory) {
        return GraphDirectory(address(this));
    }

    function _subgraphService() private view returns (SubgraphService) {
        return SubgraphService(address(this));
    }

    function _get(StorageManager storage self, bytes16 agreementId) private view returns (AgreementWrapper memory) {
        return
            AgreementWrapper({
                agreement: self.agreements[agreementId],
                collectorAgreement: _directory().recurringCollector().getAgreement(agreementId)
            });
    }
}
