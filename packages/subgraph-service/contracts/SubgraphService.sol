// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IGraphTallyCollector } from "@graphprotocol/horizon/contracts/interfaces/IGraphTallyCollector.sol";
import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { MulticallUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { DataServicePausableUpgradeable } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServicePausableUpgradeable.sol";
import { DataService } from "@graphprotocol/horizon/contracts/data-service/DataService.sol";
import { DataServiceFees } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServiceFees.sol";
import { Directory } from "./utilities/Directory.sol";
import { AllocationManager } from "./utilities/AllocationManager.sol";
import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { Decoder } from "./Decoder.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { LegacyAllocation } from "./libraries/LegacyAllocation.sol";

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";

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
    Decoder,
    IRewardsIssuer,
    ISubgraphService
{
    using PPMMath for uint256;
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;
    using TokenUtils for IGraphToken;

    /**
     * @notice Checks that an indexer is registered
     * @param indexer The address of the indexer
     */
    modifier onlyRegisteredIndexer(address indexer) {
        require(indexers[indexer].registeredAt != 0, SubgraphServiceIndexerNotRegistered(indexer));
        _;
    }

    /**
     * @notice Constructor for the SubgraphService contract
     * @dev DataService and Directory constructors set a bunch of immutable variables
     * @param graphController The address of the Graph Controller contract
     * @param disputeManager The address of the DisputeManager contract
     * @param graphTallyCollector The address of the GraphTallyCollector contract
     * @param curation The address of the Curation contract
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
        uint256 stakeToFeesRatio
    ) external initializer {
        __Ownable_init(owner);
        __Multicall_init();
        __DataService_init();
        __DataServicePausable_init();
        __AllocationManager_init("SubgraphService", "1.0");

        _setProvisionTokensRange(minimumProvisionTokens, type(uint256).max);
        _setDelegationRatio(maximumDelegationRatio);
        _setStakeToFeesRatio(stakeToFeesRatio);
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
     *  - address `url`: The URL of the indexer
     *  - string `geohash`: The geohash of the indexer
     *  - address `rewardsDestination`: The address where the indexer wants to receive indexing rewards.
     *    Use zero address for automatic reprovisioning to the subgraph service.
     */
    /// @inheritdoc IDataService
    function register(
        address indexer,
        bytes calldata data
    ) external override onlyAuthorizedForProvision(indexer) onlyValidProvision(indexer) whenNotPaused {
        (string memory url, string memory geohash, address rewardsDestination) = abi.decode(
            data,
            (string, string, address)
        );

        require(bytes(url).length > 0, SubgraphServiceEmptyUrl());
        require(bytes(geohash).length > 0, SubgraphServiceEmptyGeohash());
        require(indexers[indexer].registeredAt == 0, SubgraphServiceIndexerAlreadyRegistered());

        // Register the indexer
        indexers[indexer] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });
        if (rewardsDestination != address(0)) {
            _setRewardsDestination(indexer, rewardsDestination);
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
    ) external override onlyAuthorizedForProvision(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _checkProvisionTokens(indexer);
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
        _cancelAllocationIndexingAgreement(allocationId);
        _closeAllocation(allocationId);
        emit ServiceStopped(indexer, data);
    }

    /**
     * @notice Collects payment for the service provided by the indexer
     * Allows collecting different types of payments such as query fees and indexing rewards.
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
     *
     * @param indexer The address of the indexer
     * @param paymentType The type of payment to collect as defined in {IGraphPayments}
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
            IGraphTallyCollector.SignedRAV memory signedRav = abi.decode(data, (IGraphTallyCollector.SignedRAV));
            require(
                signedRav.rav.serviceProvider == indexer,
                SubgraphServiceIndexerMismatch(signedRav.rav.serviceProvider, indexer)
            );
            paymentCollected = _collectQueryFees(signedRav);
        } else if (paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            (address allocationId, bytes32 poi) = abi.decode(data, (address, bytes32));
            require(
                _allocations.get(allocationId).indexer == indexer,
                SubgraphServiceAllocationNotAuthorized(indexer, allocationId)
            );
            paymentCollected = _collectIndexingRewards(allocationId, poi, _delegationRatio);
        } else if (paymentType == IGraphPayments.PaymentTypes.IndexingFee) {
            (bytes16 agreementId, bytes memory iaCollectionData) = _decodeCollectIndexingFeeData(data);

            paymentCollected = _collectIndexingFees(agreementId, iaCollectionData);
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
        _cancelAllocationIndexingAgreement(allocationId);
        _closeAllocation(allocationId);
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
    function setRewardsDestination(address rewardsDestination) external override {
        _setRewardsDestination(msg.sender, rewardsDestination);
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
    function setMaxPOIStaleness(uint256 maxPOIStaleness) external override onlyOwner {
        _setMaxPOIStaleness(maxPOIStaleness);
    }

    /// @inheritdoc ISubgraphService
    function setCurationCut(uint256 curationCut) external override onlyOwner {
        require(PPMMath.isValidPPM(curationCut), SubgraphServiceInvalidCurationCut(curationCut));
        curationFeesCut = curationCut;
        emit CurationCutSet(curationCut);
    }

    /// @inheritdoc ISubgraphService
    function getAllocation(address allocationId) external view override returns (Allocation.State memory) {
        return _allocations[allocationId];
    }

    /// @inheritdoc IRewardsIssuer
    function getAllocationData(
        address allocationId
    ) external view override returns (address, bytes32, uint256, uint256, uint256) {
        Allocation.State memory allo = _allocations[allocationId];
        return (
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

    // -- Data service parameter getters --
    /**
     * @notice Getter for the accepted thawing period range for provisions
     * @dev This override ensures {ProvisionManager} uses the thawing period from the {DisputeManager}
     * @return The minimum thawing period which is defined by {DisputeManager-getDisputePeriod}
     * @return The maximum is unbounded
     */
    function _getThawingPeriodRange() internal view override returns (uint64, uint64) {
        return (_disputeManager().getDisputePeriod(), DEFAULT_MAX_THAWING_PERIOD);
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
     * @param _signedRav Signed RAV
     * @return The amount of fees collected
     */
    function _collectQueryFees(IGraphTallyCollector.SignedRAV memory _signedRav) private returns (uint256) {
        address indexer = _signedRav.rav.serviceProvider;

        // Check that collectionId (256 bits) is a valid address (160 bits)
        // collectionId is expected to be a zero padded address so it's safe to cast to uint160
        require(
            uint256(_signedRav.rav.collectionId) <= type(uint160).max,
            SubgraphServiceInvalidCollectionId(_signedRav.rav.collectionId)
        );
        address allocationId = address(uint160(uint256(_signedRav.rav.collectionId)));
        Allocation.State memory allocation = _allocations.get(allocationId);

        // Check RAV is consistent - RAV indexer must match the allocation's indexer
        require(allocation.indexer == indexer, SubgraphServiceInvalidRAV(indexer, allocation.indexer));
        bytes32 subgraphDeploymentId = allocation.subgraphDeploymentId;

        // release expired stake claims
        _releaseStake(indexer, 0);

        // Collect from GraphPayments - only curators cut is sent back to the subgraph service
        uint256 balanceBefore = _graphToken().balanceOf(address(this));

        uint256 curationCut = _curation().isCurated(subgraphDeploymentId) ? curationFeesCut : 0;
        uint256 tokensCollected = _graphTallyCollector().collect(
            IGraphPayments.PaymentTypes.QueryFee,
            abi.encode(_signedRav, curationCut)
        );

        uint256 balanceAfter = _graphToken().balanceOf(address(this));
        require(balanceAfter >= balanceBefore, SubgraphServiceInconsistentCollection(balanceBefore, balanceAfter));
        uint256 tokensCurators = balanceAfter - balanceBefore;

        if (tokensCollected > 0) {
            // lock stake as economic security for fees
            uint256 tokensToLock = tokensCollected * stakeToFeesRatio;
            uint256 unlockTimestamp = block.timestamp + _disputeManager().getDisputePeriod();
            _lockStake(indexer, tokensToLock, unlockTimestamp);

            if (tokensCurators > 0) {
                // curation collection changes subgraph signal so we take rewards snapshot
                _graphRewardsManager().onSubgraphSignalUpdate(subgraphDeploymentId);

                // Send GRT and bookkeep by calling collect()
                _graphToken().pushTokens(address(_curation()), tokensCurators);
                _curation().collect(subgraphDeploymentId, tokensCurators);
            }
        }

        emit QueryFeesCollected(indexer, _signedRav.rav.payer, tokensCollected, tokensCurators);
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

    /// @notice Sentinel value to indicate an agreement has been canceled
    uint256 private constant CANCELED = type(uint256).max;

    /// @notice Tracks indexing agreements
    mapping(bytes16 agreementId => IndexingAgreementData data) public indexingAgreements;

    /// @notice Tracks indexing agreements parameters (V1)
    mapping(bytes16 agreementId => IndexingAgreementTermsV1 data) public indexingAgreementTermsV1;

    /// @notice Lookup agreement ID by allocation ID
    mapping(address allocationId => bytes16 agreementId) public allocationToActiveAgreementId;

    /**
     * @notice Accept an indexing agreement.
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
     * @dev signedRCA.rca.metadata is an encoding of {ISubgraphService.AcceptIndexingAgreementMetadata}
     *
     * Emits {IndexingAgreementAccepted} event
     *
     * @param allocationId The id of the allocation
     * @param signedRCA The signed Recurring Collection Agreement
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
    {
        require(
            signedRCA.rca.dataService == address(this),
            SubgraphServiceIndexingAgreementWrongDataService(signedRCA.rca.dataService)
        );

        AcceptIndexingAgreementMetadata memory metadata = _decodeRCAMetadata(signedRCA.rca.metadata);
        _acceptIndexingAgreement(allocationId, signedRCA, metadata);

        emit IndexingAgreementAccepted(
            signedRCA.rca.serviceProvider,
            signedRCA.rca.payer,
            signedRCA.rca.agreementId,
            allocationId,
            metadata.subgraphDeploymentId,
            metadata.version,
            metadata.terms
        );
    }

    function upgradeIndexingAgreement(
        address indexer,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    )
        external
        whenNotPaused
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
    {
        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(signedRCAU.rcau.agreementId);
        require(_isActiveAgreement(agreement), SubgraphServiceIndexingAgreementNotActive(signedRCAU.rcau.agreementId));
        require(
            agreement.indexer == indexer,
            SubgraphServiceIndexingAgreementNotAuthorized(signedRCAU.rcau.agreementId, indexer)
        );

        UpgradeIndexingAgreementMetadata memory metadata = _decodeRCAUMetadata(signedRCAU.rcau.metadata);

        agreement.version = metadata.version;

        require(
            metadata.version == IndexingAgreementVersion.V1,
            SubgraphServiceInvalidIndexingAgreementVersion(metadata.version)
        );
        _setIndexingAgreementTermsV1(signedRCAU.rcau.agreementId, metadata.terms);

        _recurringCollector().upgrade(signedRCAU);
    }

    /**
     * @notice Cancel an indexing agreement by indexer / operator.
     * See {ISubgraphService.cancelIndexingAgreement}.
     *
     * @dev Can only be canceled on behalf of a valid indexer.
     *
     * Requirements:
     * - The indexer must be registered
     * - The caller must be authorized by the indexer
     * - The provision must be valid according to the subgraph service rules
     * - The agreement must be active
     *
     * Emits {IndexingAgreementCanceled} event
     *
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
        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(agreementId);
        require(_isActiveAgreement(agreement), SubgraphServiceIndexingAgreementNotActive(agreementId));
        require(
            agreement.indexer == indexer,
            SubgraphServiceIndexingAgreementNonCancelableBy(agreement.indexer, indexer)
        );
        _cancelIndexingAgreement(agreementId, agreement, CancelIndexingAgreementBy.Indexer);
    }

    function _cancelAllocationIndexingAgreement(address _allocationId) internal {
        bytes16 agreementId = allocationToActiveAgreementId[_allocationId];
        if (agreementId == bytes16(0)) {
            return;
        }

        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(agreementId);
        if (!_isActiveAgreement(agreement)) {
            return;
        }

        _cancelIndexingAgreement(agreementId, agreement, CancelIndexingAgreementBy.Payer);
    }

    /**
     * @notice Cancel an indexing agreement by payer / signer.
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
        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(agreementId);
        require(_isActiveAgreement(agreement), SubgraphServiceIndexingAgreementNotActive(agreementId));
        require(
            _recurringCollector().isAuthorized(agreement.payer, msg.sender),
            SubgraphServiceIndexingAgreementNonCancelableBy(agreement.payer, msg.sender)
        );
        _cancelIndexingAgreement(agreementId, agreement, CancelIndexingAgreementBy.Payer);
    }

    function getIndexingAgreement(bytes16 agreementId) external view returns (IndexingAgreementData memory) {
        return indexingAgreements[agreementId];
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
     * @param _agreementId The id of the indexing agreement
     * @param _data The indexing agreement collection data
     * @return The amount of fees collected
     */
    function _collectIndexingFees(bytes16 _agreementId, bytes memory _data) private returns (uint256) {
        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(_agreementId);
        require(_isActiveAgreement(agreement), SubgraphServiceIndexingAgreementNotActive(_agreementId));
        Allocation.State memory allocation = _requireValidAllocation(agreement.allocationId, agreement.indexer);

        require(
            agreement.version == IndexingAgreementVersion.V1,
            SubgraphServiceInvalidIndexingAgreementVersion(agreement.version)
        );
        (uint256 entities, bytes32 poi, uint256 poiEpoch) = _decodeCollectIndexingFeeDataV1(_data);

        uint256 tokensToCollect = (poi == bytes32(0) && entities == 0)
            ? 0
            : _indexingAgreementTokensToCollect(_agreementId, agreement, entities);
        agreement.lastCollectionAt = block.timestamp;

        uint256 tokensCollected = _indexingAgreementCollect(
            _agreementId,
            bytes32(uint256(uint160(agreement.allocationId))),
            tokensToCollect
        );

        _releaseAndLockStake(agreement.indexer, tokensCollected);

        emit IndexingFeesCollectedV1(
            agreement.indexer,
            agreement.payer,
            _agreementId,
            agreement.allocationId,
            allocation.subgraphDeploymentId,
            _graphEpochManager().currentEpoch(),
            tokensCollected,
            entities,
            poi,
            poiEpoch
        );
        return tokensCollected;
    }

    function _acceptIndexingAgreement(
        address _allocationId,
        IRecurringCollector.SignedRCA calldata _signedRCA,
        AcceptIndexingAgreementMetadata memory _agreementMetadata
    ) private {
        Allocation.State memory allocation = _requireValidAllocation(_allocationId, _signedRCA.rca.serviceProvider);
        require(
            allocation.subgraphDeploymentId == _agreementMetadata.subgraphDeploymentId,
            SubgraphServiceIndexingAgreementDeploymentIdMismatch(
                _agreementMetadata.subgraphDeploymentId,
                _allocationId,
                allocation.subgraphDeploymentId
            )
        );

        IndexingAgreementData storage agreement = _getForUpdateIndexingAgreement(_signedRCA.rca.agreementId);
        require(agreement.acceptedAt == 0, SubgraphServiceIndexingAgreementAlreadyAccepted(_signedRCA.rca.agreementId));

        require(_signedRCA.rca.agreementId != bytes16(0), SubgraphServiceIndexingAgreementIdZero());
        require(
            allocationToActiveAgreementId[_allocationId] == bytes16(0),
            SubgraphServiceAllocationAlreadyHasIndexingAgreement(_allocationId)
        );
        allocationToActiveAgreementId[_allocationId] = _signedRCA.rca.agreementId;

        agreement.indexer = _signedRCA.rca.serviceProvider;
        agreement.payer = _signedRCA.rca.payer;
        agreement.version = _agreementMetadata.version;
        agreement.allocationId = _allocationId;
        agreement.acceptedAt = block.timestamp;

        require(
            _agreementMetadata.version == IndexingAgreementVersion.V1,
            SubgraphServiceInvalidIndexingAgreementVersion(_agreementMetadata.version)
        );
        _setIndexingAgreementTermsV1(_signedRCA.rca.agreementId, _agreementMetadata.terms);

        _recurringCollector().accept(_signedRCA);
    }

    function _setIndexingAgreementTermsV1(bytes16 _agreementId, bytes memory _data) private {
        IndexingAgreementTermsV1 memory newTerms = _decodeIndexingAgreementTermsV1(_data);
        IndexingAgreementTermsV1 storage storedTerms = _getForUpdateIndexingAgreementTermsV1(_agreementId);
        storedTerms.tokensPerSecond = newTerms.tokensPerSecond;
        storedTerms.tokensPerEntityPerSecond = newTerms.tokensPerEntityPerSecond;
    }

    function _indexingAgreementCollect(
        bytes16 _agreementId,
        bytes32 _collectionId,
        uint256 _tokensToCollect
    ) private returns (uint256) {
        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                agreementId: _agreementId,
                collectionId: _collectionId,
                tokens: _tokensToCollect,
                dataServiceCut: 0
            })
        );
        return _recurringCollector().collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function _releaseAndLockStake(address _indexer, uint256 _tokensCollected) private {
        _releaseStake(_indexer, 0);
        if (_tokensCollected > 0) {
            // lock stake as economic security for fees
            _lockStake(
                _indexer,
                _tokensCollected * stakeToFeesRatio,
                block.timestamp + _disputeManager().getDisputePeriod()
            );
        }
    }

    enum CancelIndexingAgreementBy {
        Indexer,
        Payer
    }

    function _cancelIndexingAgreement(
        bytes16 _agreementId,
        IndexingAgreementData storage _agreement,
        CancelIndexingAgreementBy _cancelBy
    ) private {
        _agreement.acceptedAt = CANCELED;
        delete allocationToActiveAgreementId[_agreement.allocationId];

        _recurringCollector().cancel(_agreementId);

        emit IndexingAgreementCanceled(
            _agreement.indexer,
            _agreement.payer,
            _agreementId,
            _cancelBy == CancelIndexingAgreementBy.Indexer ? _agreement.indexer : _agreement.payer
        );
    }

    function _indexingAgreementTokensToCollect(
        bytes16 _agreementId,
        IndexingAgreementData memory _agreement,
        uint256 _entities
    ) private view returns (uint256) {
        IndexingAgreementTermsV1 memory termsV1 = _getIndexingAgreementTermsV1(_agreementId);

        uint256 collectionSeconds = block.timestamp;
        collectionSeconds -= _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;

        // FIX-ME: this is bad because it encourages indexers to collect at max seconds allowed to maximize collection.
        return collectionSeconds * (termsV1.tokensPerSecond + termsV1.tokensPerEntityPerSecond * _entities);
    }

    function _getForUpdateIndexingAgreement(bytes16 _agreementId) private view returns (IndexingAgreementData storage) {
        return indexingAgreements[_agreementId];
    }

    function _getIndexingAgreement(bytes16 _agreementId) private view returns (IndexingAgreementData memory) {
        return indexingAgreements[_agreementId];
    }

    function _getForUpdateIndexingAgreementTermsV1(
        bytes16 _agreementId
    ) private view returns (IndexingAgreementTermsV1 storage) {
        return indexingAgreementTermsV1[_agreementId];
    }

    function _getIndexingAgreementTermsV1(bytes16 _agreementId) private view returns (IndexingAgreementTermsV1 memory) {
        return indexingAgreementTermsV1[_agreementId];
    }

    function _requireValidAllocation(
        address _allocationId,
        address _indexer
    ) private view returns (Allocation.State memory) {
        Allocation.State memory allocation = _allocations.get(_allocationId);
        require(allocation.indexer == _indexer, SubgraphServiceAllocationNotAuthorized(_indexer, _allocationId));
        require(allocation.isOpen(), AllocationManagerAllocationClosed(_allocationId));

        return allocation;
    }

    function _requireValidCollectionId(bytes32 _collectionId) private pure returns (address) {
        // Check that collectionId (256 bits) is a valid address (160 bits)
        require(uint256(_collectionId) <= type(uint160).max, SubgraphServiceInvalidCollectionId(_collectionId));
        return address(uint160(uint256(_collectionId)));
    }

    function _isActiveAgreement(IndexingAgreementData memory _agreement) private pure returns (bool) {
        return _agreement.acceptedAt > 0 && _agreement.acceptedAt != CANCELED;
    }
}
