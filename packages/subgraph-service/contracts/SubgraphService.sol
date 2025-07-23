// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphTallyCollector } from "@graphprotocol/horizon/contracts/interfaces/IGraphTallyCollector.sol";
import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { DataServicePausableUpgradeable } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServicePausableUpgradeable.sol";
import { DataService } from "@graphprotocol/horizon/contracts/data-service/DataService.sol";
import { DataServiceFees } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServiceFees.sol";
import { Directory } from "./utilities/Directory.sol";
import { AllocationManager } from "./utilities/AllocationManager.sol";
import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { LegacyAllocation } from "./libraries/LegacyAllocation.sol";
import { IndexingAgreementDecoder } from "./libraries/IndexingAgreementDecoder.sol";
import { IndexingAgreement } from "./libraries/IndexingAgreement.sol";

/**
 * @title SubgraphService contract
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract SubgraphService is
    Initializable,
    OwnableUpgradeable,
    MulticallUpgradeable,
    DataService,
    DataServicePausableUpgradeable,
    DataServiceFees,
    Directory,
    AllocationManager,
    SubgraphServiceV1Storage,
    IRewardsIssuer,
    ISubgraphService
{
    using PPMMath for uint256;
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;
    using TokenUtils for IGraphToken;
    using IndexingAgreement for IndexingAgreement.StorageManager;

    /**
     * @notice Checks that an indexer is registered
     * @param indexer The address of the indexer
     */
    modifier onlyRegisteredIndexer(address indexer) {
        _requireRegisteredIndexer(indexer);
        _;
    }

    /**
     * @notice Constructor for the SubgraphService contract
     * @dev DataService and Directory constructors set a bunch of immutable variables
     * @param graphController The address of the Graph Controller contract
     * @param disputeManager The address of the DisputeManager contract
     * @param graphTallyCollector The address of the GraphTallyCollector contract
     * @param curation The address of the Curation contract
     * @param recurringCollector The address of the RecurringCollector contract
     */
    constructor(
        address graphController,
        address disputeManager,
        address graphTallyCollector,
        address curation,
        address recurringCollector
    )
        DataService(graphController)
        Directory(address(this), disputeManager, graphTallyCollector, curation, recurringCollector)
    {
        _disableInitializers();
    }

    /// @inheritdoc ISubgraphService
    function initialize(
        address owner,
        uint256 minimumProvisionTokens,
        uint32 maximumDelegationRatio,
        uint256 stakeToFeesRatio_
    ) external initializer {
        __Ownable_init(owner);
        __Multicall_init();
        __DataService_init();
        __DataServicePausable_init();
        __AllocationManager_init("SubgraphService", "1.0");

        _setProvisionTokensRange(minimumProvisionTokens, type(uint256).max);
        _setDelegationRatio(maximumDelegationRatio);
        _setStakeToFeesRatio(stakeToFeesRatio_);
    }

    /**
     * @notice
     * @dev Implements {IDataService.register}
     *
     * Requirements:
     * - The indexer must not be already registered
     * - The URL must not be empty
     * - The provision must be valid according to the subgraph service rules
     *
     * Emits a {ServiceProviderRegistered} event
     *
     * @param indexer The address of the indexer to register
     * @param data Encoded registration data:
     *  - string `url`: The URL of the indexer
     *  - string `geohash`: The geohash of the indexer
     *  - address `paymentsDestination`: The address where the indexer wants to receive payments.
     *    Use zero address for automatically restaking payments.
     */
    /// @inheritdoc IDataService
    function register(
        address indexer,
        bytes calldata data
    ) external override onlyAuthorizedForProvision(indexer) onlyValidProvision(indexer) whenNotPaused {
        (string memory url, string memory geohash, address paymentsDestination_) = abi.decode(
            data,
            (string, string, address)
        );

        require(bytes(url).length > 0, SubgraphServiceEmptyUrl());
        require(bytes(geohash).length > 0, SubgraphServiceEmptyGeohash());
        require(indexers[indexer].registeredAt == 0, SubgraphServiceIndexerAlreadyRegistered());

        // Register the indexer
        indexers[indexer] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });
        if (paymentsDestination_ != address(0)) {
            _setPaymentsDestination(indexer, paymentsDestination_);
        }

        emit ServiceProviderRegistered(indexer, data);
    }

    /**
     * @notice Accept staged parameters in the provision of a service provider
     * @dev Implements {IDataService-acceptProvisionPendingParameters}
     *
     * Requirements:
     * - The indexer must be registered
     * - Must have previously staged provision parameters, using {IHorizonStaking-setProvisionParameters}
     * - The new provision parameters must be valid according to the subgraph service rules
     *
     * Emits a {ProvisionPendingParametersAccepted} event
     *
     * @param indexer The address of the indexer to accept the provision for
     */
    /// @inheritdoc IDataService
    function acceptProvisionPendingParameters(
        address indexer,
        bytes calldata
    ) external override onlyAuthorizedForProvision(indexer) whenNotPaused {
        _acceptProvisionParameters(indexer);
        emit ProvisionPendingParametersAccepted(indexer);
    }

    /**
     * @notice Allocates tokens to subgraph deployment, manifesting the indexer's commitment to index it
     * @dev This is the equivalent of the `allocate` function in the legacy Staking contract.
     *
     * Requirements:
     * - The indexer must be registered
     * - The provision must be valid according to the subgraph service rules
     * - Allocation id cannot be zero
     * - Allocation id cannot be reused from the legacy staking contract
     * - The indexer must have enough available tokens to allocate
     *
     * The `allocationProof` is a 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationId)`.
     *
     * See {AllocationManager-allocate} for more details.
     *
     * Emits {ServiceStarted} and {AllocationCreated} events
     *
     * @param indexer The address of the indexer
     * @param data Encoded data:
     * - bytes32 `subgraphDeploymentId`: The id of the subgraph deployment
     * - uint256 `tokens`: The amount of tokens to allocate
     * - address `allocationId`: The id of the allocation
     * - bytes `allocationProof`: Signed proof of the allocation id address ownership
     */
    /// @inheritdoc IDataService
    function startService(
        address indexer,
        bytes calldata data
    )
        external
        override
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        whenNotPaused
    {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof, _delegationRatio);
        emit ServiceStarted(indexer, data);
    }

    /**
     * @notice Close an allocation, indicating that the indexer has stopped indexing the subgraph deployment
     * @dev This is the equivalent of the `closeAllocation` function in the legacy Staking contract.
     * There are a few notable differences with the legacy function:
     * - allocations are nowlong lived. All service payments, including indexing rewards, should be collected periodically
     * without the need of closing the allocation. Allocations should only be closed when indexers want to reclaim the allocated
     * tokens for other purposes.
     * - No POI is required to close an allocation. Indexers should present POIs to collect indexing rewards using {collect}.
     *
     * Requirements:
     * - The indexer must be registered
     * - Allocation must exist and be open
     *
     * Emits {ServiceStopped} and {AllocationClosed} events
     *
     * @param indexer The address of the indexer
     * @param data Encoded data:
     * - address `allocationId`: The id of the allocation
     */
    /// @inheritdoc IDataService
    function stopService(
        address indexer,
        bytes calldata data
    ) external override onlyAuthorizedForProvision(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        address allocationId = abi.decode(data, (address));
        require(
            _allocations.get(allocationId).indexer == indexer,
            SubgraphServiceAllocationNotAuthorized(indexer, allocationId)
        );
        _onCloseAllocation(allocationId, false);
        _closeAllocation(allocationId, false);
        emit ServiceStopped(indexer, data);
    }

    /**
     * @notice Collects payment for the service provided by the indexer
     * Allows collecting different types of payments such as query fees, indexing rewards and indexing fees.
     * It uses Graph Horizon payments protocol to process payments.
     * Reverts if the payment type is not supported.
     * @dev This function is the equivalent of the `collect` function for query fees and the `closeAllocation` function
     * for indexing rewards in the legacy Staking contract.
     *
     * Requirements:
     * - The indexer must be registered
     * - The provision must be valid according to the subgraph service rules
     *
     * Emits a {ServicePaymentCollected} event. Emits payment type specific events.
     *
     * For query fees, see {SubgraphService-_collectQueryFees} for more details.
     * For indexing rewards, see {AllocationManager-_collectIndexingRewards} for more details.
     * For indexing fees, see {SubgraphService-_collectIndexingFees} for more details.
     *
     * Note that collecting any type of payment will require locking provisioned stake as collateral for a period of time.
     * All types of payment share the same pool of provisioned stake however they each have separate accounting:
     * - Indexing rewards can make full use of the available stake
     * - Query and indexing fees share the pool, combined they can also make full use of the available stake
     *
     * @param indexer The address of the indexer
     * @param paymentType The type of payment to collect as defined in {IGraphPayments}
     * @param data Encoded data:
     *    - For query fees:
     *      - IGraphTallyCollector.SignedRAV `signedRav`: The signed RAV
     *    - For indexing rewards:
     *      - address `allocationId`: The id of the allocation
     *      - bytes32 `poi`: The POI being presented
     *      - bytes `poiMetadata`: The metadata associated with the POI. See {AllocationManager-_collectIndexingRewards} for more details.
     *    - For indexing fees:
     *      - bytes16 `agreementId`: The id of the indexing agreement
     *      - bytes `agreementCollectionMetadata`: The metadata required by the indexing agreement version.
     */
    /// @inheritdoc IDataService
    function collect(
        address indexer,
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    )
        external
        override
        whenNotPaused
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        returns (uint256)
    {
        uint256 paymentCollected = 0;

        if (paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            paymentCollected = _collectQueryFees(indexer, data);
        } else if (paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            paymentCollected = _collectIndexingRewards(indexer, data);
        } else if (paymentType == IGraphPayments.PaymentTypes.IndexingFee) {
            (bytes16 agreementId, bytes memory iaCollectionData) = IndexingAgreementDecoder.decodeCollectData(data);
            paymentCollected = _collectIndexingFees(
                indexer,
                agreementId,
                paymentsDestination[indexer],
                iaCollectionData
            );
        } else {
            revert SubgraphServiceInvalidPaymentType(paymentType);
        }

        emit ServicePaymentCollected(indexer, paymentType, paymentCollected);
        return paymentCollected;
    }

    /**
     * @notice See {IHorizonStaking-slash} for more details.
     * @dev Slashing is delegated to the {DisputeManager} contract which is the only one that can call this
     * function.
     */
    /// @inheritdoc IDataService
    function slash(address indexer, bytes calldata data) external override onlyDisputeManager {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        _graphStaking().slash(indexer, tokens, reward, address(_disputeManager()));
        emit ServiceProviderSlashed(indexer, tokens);
    }

    /// @inheritdoc ISubgraphService
    function closeStaleAllocation(address allocationId) external override whenNotPaused {
        Allocation.State memory allocation = _allocations.get(allocationId);
        require(allocation.isStale(maxPOIStaleness), SubgraphServiceCannotForceCloseAllocation(allocationId));
        require(!allocation.isAltruistic(), SubgraphServiceAllocationIsAltruistic(allocationId));
        _onCloseAllocation(allocationId, true);
        _closeAllocation(allocationId, true);
    }

    /// @inheritdoc ISubgraphService
    function resizeAllocation(
        address indexer,
        address allocationId,
        uint256 tokens
    )
        external
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        whenNotPaused
    {
        require(
            _allocations.get(allocationId).indexer == indexer,
            SubgraphServiceAllocationNotAuthorized(indexer, allocationId)
        );
        _resizeAllocation(allocationId, tokens, _delegationRatio);
    }

    /// @inheritdoc ISubgraphService
    function migrateLegacyAllocation(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentID
    ) external override onlyOwner {
        _migrateLegacyAllocation(indexer, allocationId, subgraphDeploymentID);
    }

    /// @inheritdoc ISubgraphService
    function setPauseGuardian(address pauseGuardian, bool allowed) external override onlyOwner {
        _setPauseGuardian(pauseGuardian, allowed);
    }

    /// @inheritdoc ISubgraphService
    function setPaymentsDestination(address paymentsDestination_) external override {
        _setPaymentsDestination(msg.sender, paymentsDestination_);
    }

    /// @inheritdoc ISubgraphService
    function setMinimumProvisionTokens(uint256 minimumProvisionTokens) external override onlyOwner {
        _setProvisionTokensRange(minimumProvisionTokens, DEFAULT_MAX_PROVISION_TOKENS);
    }

    /// @inheritdoc ISubgraphService
    function setDelegationRatio(uint32 delegationRatio) external override onlyOwner {
        _setDelegationRatio(delegationRatio);
    }

    /// @inheritdoc ISubgraphService
    function setStakeToFeesRatio(uint256 stakeToFeesRatio_) external override onlyOwner {
        _setStakeToFeesRatio(stakeToFeesRatio_);
    }

    /// @inheritdoc ISubgraphService
    function setMaxPOIStaleness(uint256 maxPOIStaleness_) external override onlyOwner {
        _setMaxPOIStaleness(maxPOIStaleness_);
    }

    /// @inheritdoc ISubgraphService
    function setCurationCut(uint256 curationCut) external override onlyOwner {
        require(PPMMath.isValidPPM(curationCut), SubgraphServiceInvalidCurationCut(curationCut));
        curationFeesCut = curationCut;
        emit CurationCutSet(curationCut);
    }

    /**
     * @inheritdoc ISubgraphService
     * @notice Accept an indexing agreement.
     *
     * See {ISubgraphService.acceptIndexingAgreement}.
     *
     * Requirements:
     * - The agreement's indexer must be registered
     * - The caller must be authorized by the agreement's indexer
     * - The provision must be valid according to the subgraph service rules
     * - Allocation must belong to the indexer and be open
     * - Agreement must be for this data service
     * - Agreement's subgraph deployment must match the allocation's subgraph deployment
     * - Agreement must not have been accepted before
     * - Allocation must not have an agreement already
     *
     * @dev signedRCA.rca.metadata is an encoding of {IndexingAgreement.AcceptIndexingAgreementMetadata}
     *
     * Emits {IndexingAgreement.IndexingAgreementAccepted} event
     *
     * @param allocationId The id of the allocation
     * @param signedRCA The signed Recurring Collection Agreement
     * @return agreementId The ID of the accepted indexing agreement
     */
    function acceptIndexingAgreement(
        address allocationId,
        IRecurringCollector.SignedRCA calldata signedRCA
    )
        external
        whenNotPaused
        onlyAuthorizedForProvision(signedRCA.rca.serviceProvider)
        onlyValidProvision(signedRCA.rca.serviceProvider)
        onlyRegisteredIndexer(signedRCA.rca.serviceProvider)
        returns (bytes16)
    {
        return IndexingAgreement._getStorageManager().accept(_allocations, allocationId, signedRCA);
    }

    /**
     * @inheritdoc ISubgraphService
     * @notice Update an indexing agreement.
     *
     * See {IndexingAgreement.update}.
     *
     * Requirements:
     * - The contract must not be paused
     * - The indexer must be valid
     *
     * @param indexer The indexer address
     * @param signedRCAU The signed Recurring Collection Agreement Update
     */
    function updateIndexingAgreement(
        address indexer,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    )
        external
        whenNotPaused
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
    {
        IndexingAgreement._getStorageManager().update(indexer, signedRCAU);
    }

    /**
     * @inheritdoc ISubgraphService
     * @notice Cancel an indexing agreement by indexer / operator.
     *
     * See {IndexingAgreement.cancel}.
     *
     * @dev Can only be canceled on behalf of a valid indexer.
     *
     * Requirements:
     * - The contract must not be paused
     * - The indexer must be valid
     *
     * @param indexer The indexer address
     * @param agreementId The id of the agreement
     */
    function cancelIndexingAgreement(
        address indexer,
        bytes16 agreementId
    )
        external
        whenNotPaused
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
    {
        IndexingAgreement._getStorageManager().cancel(indexer, agreementId);
    }

    /**
     * @inheritdoc ISubgraphService
     * @notice Cancel an indexing agreement by payer / signer.
     *
     * See {ISubgraphService.cancelIndexingAgreementByPayer}.
     *
     * Requirements:
     * - The caller must be authorized by the payer
     * - The agreement must be active
     *
     * Emits {IndexingAgreementCanceled} event
     *
     * @param agreementId The id of the agreement
     */
    function cancelIndexingAgreementByPayer(bytes16 agreementId) external whenNotPaused {
        IndexingAgreement._getStorageManager().cancelByPayer(agreementId);
    }

    /// @inheritdoc ISubgraphService
    function getIndexingAgreement(
        bytes16 agreementId
    ) external view returns (IndexingAgreement.AgreementWrapper memory) {
        return IndexingAgreement._getStorageManager().get(agreementId);
    }

    /// @inheritdoc ISubgraphService
    function getAllocation(address allocationId) external view override returns (Allocation.State memory) {
        return _allocations[allocationId];
    }

    /// @inheritdoc IRewardsIssuer
    function getAllocationData(
        address allocationId
    ) external view override returns (bool, address, bytes32, uint256, uint256, uint256) {
        Allocation.State memory allo = _allocations[allocationId];
        return (
            allo.isOpen(),
            allo.indexer,
            allo.subgraphDeploymentId,
            allo.tokens,
            allo.accRewardsPerAllocatedToken,
            allo.accRewardsPending
        );
    }

    /// @inheritdoc IRewardsIssuer
    function getSubgraphAllocatedTokens(bytes32 subgraphDeploymentId) external view override returns (uint256) {
        return _subgraphAllocatedTokens[subgraphDeploymentId];
    }

    /// @inheritdoc ISubgraphService
    function getLegacyAllocation(address allocationId) external view override returns (LegacyAllocation.State memory) {
        return _legacyAllocations[allocationId];
    }

    /// @inheritdoc ISubgraphService
    function getDisputeManager() external view override returns (address) {
        return address(_disputeManager());
    }

    /// @inheritdoc ISubgraphService
    function getGraphTallyCollector() external view override returns (address) {
        return address(_graphTallyCollector());
    }

    /// @inheritdoc ISubgraphService
    function getCuration() external view override returns (address) {
        return address(_curation());
    }

    /// @inheritdoc ISubgraphService
    function encodeAllocationProof(address indexer, address allocationId) external view override returns (bytes32) {
        return _encodeAllocationProof(indexer, allocationId);
    }

    /// @inheritdoc ISubgraphService
    function isOverAllocated(address indexer) external view override returns (bool) {
        return _isOverAllocated(indexer, _delegationRatio);
    }

    /**
     * @notice Internal function to handle closing an allocation
     * @dev This function is called when an allocation is closed, either by the indexer or by a third party
     * @param _allocationId The id of the allocation being closed
     * @param _stale Whether the allocation is stale or not
     */
    function _onCloseAllocation(address _allocationId, bool _stale) internal {
        IndexingAgreement._getStorageManager().onCloseAllocation(_allocationId, _stale);
    }

    /**
     * @notice Sets the payments destination for an indexer to receive payments
     * @dev Emits a {PaymentsDestinationSet} event
     * @param _indexer The address of the indexer
     * @param _paymentsDestination The address where payments should be sent
     */
    function _setPaymentsDestination(address _indexer, address _paymentsDestination) internal {
        paymentsDestination[_indexer] = _paymentsDestination;
        emit PaymentsDestinationSet(_indexer, _paymentsDestination);
    }

    /**
     * @notice Requires that the indexer is registered
     * @param _indexer The address of the indexer
     */
    function _requireRegisteredIndexer(address _indexer) internal view {
        require(indexers[_indexer].registeredAt != 0, SubgraphServiceIndexerNotRegistered(_indexer));
    }

    // -- Data service parameter getters --
    /**
     * @notice Getter for the accepted thawing period range for provisions
     * The accepted range is just the dispute period defined by {DisputeManager-getDisputePeriod}
     * @dev This override ensures {ProvisionManager} uses the thawing period from the {DisputeManager}
     * @return The minimum thawing period - the dispute period
     * @return The maximum thawing period - the dispute period
     */
    function _getThawingPeriodRange() internal view override returns (uint64, uint64) {
        uint64 disputePeriod = _disputeManager().getDisputePeriod();
        return (disputePeriod, disputePeriod);
    }

    /**
     * @notice Getter for the accepted verifier cut range for provisions
     * @return The minimum verifier cut which is defined by the fisherman reward cut {DisputeManager-getFishermanRewardCut}
     * @return The maximum is 100% in PPM
     */
    function _getVerifierCutRange() internal view override returns (uint32, uint32) {
        return (_disputeManager().getFishermanRewardCut(), DEFAULT_MAX_VERIFIER_CUT);
    }

    /**
     * @notice Collect query fees
     * Stake equal to the amount being collected times the `stakeToFeesRatio` is locked into a stake claim.
     * This claim can be released at a later stage once expired.
     *
     * It's important to note that before collecting this function will attempt to release any expired stake claims.
     * This could lead to an out of gas error if there are too many expired claims. In that case, the indexer will need to
     * manually release the claims, see {IDataServiceFees-releaseStake}, before attempting to collect again.
     *
     * @dev This function is the equivalent of the legacy `collect` function for query fees.
     * @dev Uses the {GraphTallyCollector} to collect payment from Graph Horizon payments protocol.
     * Fees are distributed to service provider and delegators by {GraphPayments}, though curators
     * share is distributed by this function.
     *
     * Query fees can be collected on closed allocations.
     *
     * Requirements:
     * - Indexer must have enough available tokens to lock as economic security for fees
     *
     * Emits a {StakeClaimsReleased} event, and a {StakeClaimReleased} event for each claim released.
     * Emits a {StakeClaimLocked} event.
     * Emits a {QueryFeesCollected} event.
     *
     * @param _indexer The address of the indexer
     * @param _data Encoded data:
     *    - IGraphTallyCollector.SignedRAV `signedRav`: The signed RAV
     *    - uint256 `tokensToCollect`: The amount of tokens to collect. Allows partially collecting a RAV. If 0, the entire RAV will
     * be collected.
     * @return The amount of fees collected
     */
    function _collectQueryFees(address _indexer, bytes calldata _data) private returns (uint256) {
        (IGraphTallyCollector.SignedRAV memory signedRav, uint256 tokensToCollect) = abi.decode(
            _data,
            (IGraphTallyCollector.SignedRAV, uint256)
        );
        require(
            signedRav.rav.serviceProvider == _indexer,
            SubgraphServiceIndexerMismatch(signedRav.rav.serviceProvider, _indexer)
        );

        // Check that collectionId (256 bits) is a valid address (160 bits)
        // collectionId is expected to be a zero padded address so it's safe to cast to uint160
        require(
            uint256(signedRav.rav.collectionId) <= type(uint160).max,
            SubgraphServiceInvalidCollectionId(signedRav.rav.collectionId)
        );
        address allocationId = address(uint160(uint256(signedRav.rav.collectionId)));
        Allocation.State memory allocation = _allocations.get(allocationId);

        // Check RAV is consistent - RAV indexer must match the allocation's indexer
        require(allocation.indexer == _indexer, SubgraphServiceInvalidRAV(_indexer, allocation.indexer));
        bytes32 subgraphDeploymentId = allocation.subgraphDeploymentId;

        // release expired stake claims
        _releaseStake(_indexer, 0);

        // Collect from GraphPayments - only curators cut is sent back to the subgraph service
        uint256 tokensCollected;
        uint256 tokensCurators;
        {
            uint256 balanceBefore = _graphToken().balanceOf(address(this));

            tokensCollected = _graphTallyCollector().collect(
                IGraphPayments.PaymentTypes.QueryFee,
                _encodeGraphTallyData(signedRav, _curation().isCurated(subgraphDeploymentId) ? curationFeesCut : 0),
                tokensToCollect
            );

            uint256 balanceAfter = _graphToken().balanceOf(address(this));
            require(balanceAfter >= balanceBefore, SubgraphServiceInconsistentCollection(balanceBefore, balanceAfter));
            tokensCurators = balanceAfter - balanceBefore;
        }

        if (tokensCollected > 0) {
            // lock stake as economic security for fees
            _lockStake(
                _indexer,
                tokensCollected * stakeToFeesRatio,
                block.timestamp + _disputeManager().getDisputePeriod()
            );

            if (tokensCurators > 0) {
                // curation collection changes subgraph signal so we take rewards snapshot
                _graphRewardsManager().onSubgraphSignalUpdate(subgraphDeploymentId);

                // Send GRT and bookkeep by calling collect()
                _graphToken().pushTokens(address(_curation()), tokensCurators);
                _curation().collect(subgraphDeploymentId, tokensCurators);
            }
        }

        emit QueryFeesCollected(
            _indexer,
            signedRav.rav.payer,
            allocationId,
            subgraphDeploymentId,
            tokensCollected,
            tokensCurators
        );
        return tokensCollected;
    }

    /**
     * @notice Collect indexing rewards
     * @param _indexer The address of the indexer
     * @param _data Encoded data:
     *    - address `allocationId`: The id of the allocation
     *    - bytes32 `poi`: The POI being presented
     *    - bytes `poiMetadata`: The metadata associated with the POI. See {AllocationManager-_presentPOI} for more details.
     * @return The amount of indexing rewards collected
     */
    function _collectIndexingRewards(address _indexer, bytes calldata _data) private returns (uint256) {
        (address allocationId, bytes32 poi_, bytes memory poiMetadata_) = abi.decode(_data, (address, bytes32, bytes));
        require(
            _allocations.get(allocationId).indexer == _indexer,
            SubgraphServiceAllocationNotAuthorized(_indexer, allocationId)
        );
        return _presentPOI(allocationId, poi_, poiMetadata_, _delegationRatio, paymentsDestination[_indexer]);
    }

    /**
     * @notice Collect Indexing fees
     * Stake equal to the amount being collected times the `stakeToFeesRatio` is locked into a stake claim.
     * This claim can be released at a later stage once expired.
     *
     * It's important to note that before collecting this function will attempt to release any expired stake claims.
     * This could lead to an out of gas error if there are too many expired claims. In that case, the indexer will need to
     * manually release the claims, see {IDataServiceFees-releaseStake}, before attempting to collect again.
     *
     * @dev Uses the {RecurringCollector} to collect payment from Graph Horizon payments protocol.
     * Fees are distributed to service provider and delegators by {GraphPayments}
     *
     * Requirements:
     * - Indexer must have enough available tokens to lock as economic security for fees
     * - Allocation must be open
     *
     * Emits a {StakeClaimsReleased} event, and a {StakeClaimReleased} event for each claim released.
     * Emits a {StakeClaimLocked} event.
     * Emits a {IndexingFeesCollectedV1} event.
     *
     * @param _indexer The address of the indexer
     * @param _agreementId The id of the indexing agreement
     * @param _paymentsDestination The address where the fees should be sent
     * @param _data The indexing agreement collection data
     * @return The amount of fees collected
     */
    function _collectIndexingFees(
        address _indexer,
        bytes16 _agreementId,
        address _paymentsDestination,
        bytes memory _data
    ) private returns (uint256) {
        (address indexer, uint256 tokensCollected) = IndexingAgreement._getStorageManager().collect(
            _allocations,
            IndexingAgreement.CollectParams({
                indexer: _indexer,
                agreementId: _agreementId,
                currentEpoch: _graphEpochManager().currentEpoch(),
                receiverDestination: _paymentsDestination,
                data: _data
            })
        );

        _releaseStake(indexer, 0);
        if (tokensCollected > 0) {
            // lock stake as economic security for fees
            _lockStake(
                indexer,
                tokensCollected * stakeToFeesRatio,
                block.timestamp + _disputeManager().getDisputePeriod()
            );
        }

        return tokensCollected;
    }

    /**
     * @notice Set the stake to fees ratio.
     * @param _stakeToFeesRatio The stake to fees ratio
     */
    function _setStakeToFeesRatio(uint256 _stakeToFeesRatio) private {
        require(_stakeToFeesRatio != 0, SubgraphServiceInvalidZeroStakeToFeesRatio());
        stakeToFeesRatio = _stakeToFeesRatio;
        emit StakeToFeesRatioSet(_stakeToFeesRatio);
    }

    /**
     * @notice Encodes the data for the GraphTallyCollector
     * @dev The purpose of this function is just to avoid stack too deep errors
     * @param _signedRav The signed RAV
     * @param _curationCut The curation cut
     * @return The encoded data
     */
    function _encodeGraphTallyData(
        IGraphTallyCollector.SignedRAV memory _signedRav,
        uint256 _curationCut
    ) private view returns (bytes memory) {
        return abi.encode(_signedRav, _curationCut, paymentsDestination[_signedRav.rav.serviceProvider]);
    }
}
