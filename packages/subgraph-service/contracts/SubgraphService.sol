// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";
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

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { LegacyAllocation } from "./libraries/LegacyAllocation.sol";

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
     * @param tapCollector The address of the TAPCollector contract
     * @param curation The address of the Curation contract
     */
    constructor(
        address graphController,
        address disputeManager,
        address tapCollector,
        address curation
    ) DataService(graphController) Directory(address(this), disputeManager, tapCollector, curation) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @dev The thawingPeriod and verifierCut ranges are not set here because they are variables
     * on the DisputeManager. We use the {ProvisionManager} overrideable getters to get the ranges.
     * @param minimumProvisionTokens The minimum amount of provisioned tokens required to create an allocation
     * @param maximumDelegationRatio The maximum delegation ratio allowed for an allocation
     * @param stakeToFeesRatio The ratio of stake to fees to lock when collecting query fees
     */
    function initialize(
        uint256 minimumProvisionTokens,
        uint32 maximumDelegationRatio,
        uint256 stakeToFeesRatio
    ) external initializer {
        __Ownable_init(msg.sender);
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
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof, delegationRatio);
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
    function stopService(
        address indexer,
        bytes calldata data
    ) external override onlyAuthorizedForProvision(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        address allocationId = abi.decode(data, (address));
        require(
            _allocations.get(allocationId).indexer == indexer,
            SubgraphServiceAllocationNotAuthorized(indexer, allocationId)
        );
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
     * @param data Encoded data to fulfill the payment. The structure of the data depends on the payment type. See above.
     */
    function collect(
        address indexer,
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    )
        external
        override
        onlyAuthorizedForProvision(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        whenNotPaused
        returns (uint256)
    {
        uint256 paymentCollected = 0;

        if (paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            ITAPCollector.SignedRAV memory signedRav = abi.decode(data, (ITAPCollector.SignedRAV));
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
            paymentCollected = _collectIndexingRewards(allocationId, poi, delegationRatio);
        } else {
            revert SubgraphServiceInvalidPaymentType(paymentType);
        }

        emit ServicePaymentCollected(indexer, paymentType, paymentCollected);
        return paymentCollected;
    }

    /**
     * @notice Slash an indexer
     * @dev Slashing is delegated to the {DisputeManager} contract which is the only one that can call this
     * function.
     *
     * See {IHorizonStaking-slash} for more details.
     *
     * Emits a {ServiceProviderSlashed} event.
     *
     * @param indexer The address of the indexer to be slashed
     * @param data Encoded data:
     * - uint256 `tokens`: The amount of tokens to slash
     * - uint256 `reward`: The amount of tokens to reward the slasher
     */
    function slash(address indexer, bytes calldata data) external override onlyDisputeManager {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        _graphStaking().slash(indexer, tokens, reward, address(_disputeManager()));
        emit ServiceProviderSlashed(indexer, tokens);
    }

    /**
     * @notice See {ISubgraphService.closeStaleAllocation}
     */
    function closeStaleAllocation(address allocationId) external override whenNotPaused {
        Allocation.State memory allocation = _allocations.get(allocationId);
        require(allocation.isStale(maxPOIStaleness), SubgraphServiceCannotForceCloseAllocation(allocationId));
        require(!allocation.isAltruistic(), SubgraphServiceAllocationIsAltruistic(allocationId));
        _closeAllocation(allocationId);
    }

    /**
     * @notice See {ISubgraphService.resizeAllocation}
     */
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
        _resizeAllocation(allocationId, tokens, delegationRatio);
    }

    /**
     * @notice See {ISubgraphService.migrateLegacyAllocation}
     */
    function migrateLegacyAllocation(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentID
    ) external override onlyOwner {
        _migrateLegacyAllocation(indexer, allocationId, subgraphDeploymentID);
    }

    /**
     * @notice See {ISubgraphService.setPauseGuardian}
     */
    function setPauseGuardian(address pauseGuardian, bool allowed) external override onlyOwner {
        _setPauseGuardian(pauseGuardian, allowed);
    }

    /**
     * @notice See {ISubgraphService.setRewardsDestination}
     */
    function setRewardsDestination(address rewardsDestination) external override {
        _setRewardsDestination(msg.sender, rewardsDestination);
    }

    /**
     * @notice See {ISubgraphService.setMinimumProvisionTokens}
     */
    function setMinimumProvisionTokens(uint256 minimumProvisionTokens) external override onlyOwner {
        _setProvisionTokensRange(minimumProvisionTokens, DEFAULT_MAX_PROVISION_TOKENS);
    }

    /**
     * @notice See {ISubgraphService.setDelegationRatio}
     */
    function setDelegationRatio(uint32 delegationRatio) external override onlyOwner {
        _setDelegationRatio(delegationRatio);
    }

    /**
     * @notice See {ISubgraphService.setStakeToFeesRatio}
     */
    function setStakeToFeesRatio(uint256 stakeToFeesRatio_) external override onlyOwner {
        _setStakeToFeesRatio(stakeToFeesRatio_);
    }

    /**
     * @notice See {ISubgraphService.setMaxPOIStaleness}
     */
    function setMaxPOIStaleness(uint256 maxPOIStaleness) external override onlyOwner {
        _setMaxPOIStaleness(maxPOIStaleness);
    }

    /**
     * @notice See {ISubgraphService.setCurationCut}
     */
    function setCurationCut(uint256 curationCut) external override onlyOwner {
        require(PPMMath.isValidPPM(curationCut), SubgraphServiceInvalidCurationCut(curationCut));
        curationFeesCut = curationCut;
        emit CurationCutSet(curationCut);
    }

    /**
     * @notice See {ISubgraphService.getAllocation}
     */
    function getAllocation(address allocationId) external view override returns (Allocation.State memory) {
        return _allocations[allocationId];
    }

    /**
     * @notice Get allocation data to calculate rewards issuance
     * @dev Implements {IRewardsIssuer.getAllocationData}
     * @dev Note that this is slightly different than {getAllocation}. It returns an
     * unstructured subset of the allocation data, which is the minimum required to mint rewards.
     *
     * Should only be used by the {RewardsManager}.
     *
     * @param allocationId The allocation Id
     * @return indexer The indexer address
     * @return subgraphDeploymentId Subgraph deployment id for the allocation
     * @return tokens Amount of allocated tokens
     * @return accRewardsPerAllocatedToken Rewards snapshot
     * @return accRewardsPending Rewards pending to be minted due to allocation resize
     */
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

    /**
     * @notice Return the total amount of tokens allocated to subgraph.
     * @dev Implements {IRewardsIssuer.getSubgraphAllocatedTokens}
     * @dev To be used by the {RewardsManager}.
     * @param subgraphDeploymentId Deployment Id for the subgraph
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 subgraphDeploymentId) external view override returns (uint256) {
        return _subgraphAllocatedTokens[subgraphDeploymentId];
    }

    /**
     * @notice Check if an allocation is open
     * @dev Implements {IRewardsIssuer.isAllocationActive}
     * @dev To be used by the {RewardsManager}.
     *
     * @param allocationId The allocation Id
     * @return Wether or not the allocation is active
     */
    function isActiveAllocation(address allocationId) external view override returns (bool) {
        return _allocations[allocationId].isOpen();
    }

    /**
     * @notice See {ISubgraphService.getLegacyAllocation}
     */
    function getLegacyAllocation(address allocationId) external view override returns (LegacyAllocation.State memory) {
        return _legacyAllocations[allocationId];
    }

    /**
     * @notice See {ISubgraphService.encodeAllocationProof}
     */
    function encodeAllocationProof(address indexer, address allocationId) external view override returns (bytes32) {
        return _encodeAllocationProof(indexer, allocationId);
    }

    /**
     * @notice See {ISubgraphService.isStaleAllocation}
     */
    function isStaleAllocation(address allocationId) external view override returns (bool) {
        return _allocations.get(allocationId).isStale(maxPOIStaleness);
    }

    /**
     * @notice See {ISubgraphService.isOverAllocated}
     */
    function isOverAllocated(address indexer) external view override returns (bool) {
        return _isOverAllocated(indexer, delegationRatio);
    }

    // -- Data service parameter getters --
    /**
     * @notice Getter for the accepted thawing period range for provisions
     * @dev This override ensures {ProvisionManager} uses the thawing period from the {DisputeManager}
     * @return min The minimum thawing period which is defined by {DisputeManager-getDisputePeriod}
     * @return max The maximum is unbounded
     */
    function _getThawingPeriodRange() internal view override returns (uint64 min, uint64 max) {
        return (_disputeManager().getDisputePeriod(), DEFAULT_MAX_THAWING_PERIOD);
    }

    /**
     * @notice Getter for the accepted verifier cut range for provisions
     * @return min The minimum verifier cut which is defined by {DisputeManager-getVerifierCut}
     * @return max The maximum is 100% in PPM
     */
    function _getVerifierCutRange() internal view override returns (uint32 min, uint32 max) {
        return (_disputeManager().getVerifierCut(), DEFAULT_MAX_VERIFIER_CUT);
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
     * @dev Uses the {TAPCollector} to collect payment from Graph Horizon payments protocol.
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
     */
    function _collectQueryFees(ITAPCollector.SignedRAV memory _signedRav) private returns (uint256 feesCollected) {
        address indexer = _signedRav.rav.serviceProvider;

        // Check that the collectorId fits in an address (160 bits)
        require(
            uint256(_signedRav.rav.collectorId) < (1 << 160),
            SubgraphServiceInvalidCollectorId(_signedRav.rav.collectorId)
        );
        address allocationId = address(uint160(uint256(_signedRav.rav.collectorId)));
        Allocation.State memory allocation = _allocations.get(allocationId);

        // Check RAV is consistent - RAV indexer must match the allocation's indexer
        require(allocation.indexer == indexer, SubgraphServiceInvalidRAV(indexer, allocation.indexer));
        bytes32 subgraphDeploymentId = allocation.subgraphDeploymentId;

        // release expired stake claims
        _releaseStake(indexer, 0);

        // Collect from GraphPayments - only curators cut is sent back to the subgraph service
        uint256 balanceBefore = _graphToken().balanceOf(address(this));

        uint256 curationCut = _curation().isCurated(subgraphDeploymentId) ? curationFeesCut : 0;
        uint256 tokensCollected = _tapCollector().collect(
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

        emit QueryFeesCollected(indexer, tokensCollected, tokensCurators);
        return tokensCollected;
    }

    function _setStakeToFeesRatio(uint256 _stakeToFeesRatio) private {
        require(_stakeToFeesRatio != 0, SubgraphServiceInvalidZeroStakeToFeesRatio());
        stakeToFeesRatio = _stakeToFeesRatio;
        emit StakeToFeesRatioSet(_stakeToFeesRatio);
    }
}
