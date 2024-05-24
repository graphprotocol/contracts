// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DataServicePausable } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServicePausable.sol";
import { DataService } from "@graphprotocol/horizon/contracts/data-service/DataService.sol";
import { DataServiceRescuable } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServiceRescuable.sol";
import { DataServiceFees } from "@graphprotocol/horizon/contracts/data-service/extensions/DataServiceFees.sol";
import { Directory } from "./utilities/Directory.sol";
import { AllocationManager } from "./utilities/AllocationManager.sol";
import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";

import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { LegacyAllocation } from "./libraries/LegacyAllocation.sol";

// TODO: contract needs to be upgradeable
contract SubgraphService is
    Ownable,
    DataService,
    DataServicePausable,
    DataServiceRescuable,
    DataServiceFees,
    Directory,
    AllocationManager,
    SubgraphServiceV1Storage,
    IRewardsIssuer,
    ISubgraphService
{
    using PPMMath for uint256;
    using Allocation for mapping(address => Allocation.State);

    modifier onlyRegisteredIndexer(address indexer) {
        require(indexers[indexer].registeredAt != 0, SubgraphServiceIndexerNotRegistered(indexer));
        _;
    }

    /**
     * @dev Strict delegation ratio not enforced.
     */
    modifier onlyValidProvision(address indexer) override {
        _checkProvisionTokens(indexer);
        _checkProvisionParameters(indexer, false);
        _;
    }

    constructor(
        address graphController,
        address disputeManager,
        address tapVerifier,
        address curation,
        uint256 minimumProvisionTokens,
        uint32 maximumDelegationRatio
    )
        Ownable(msg.sender)
        DataService(graphController)
        Directory(address(this), tapVerifier, disputeManager, curation)
        AllocationManager("SubgraphService", "1.0")
    {
        _setProvisionTokensRange(minimumProvisionTokens, type(uint256).max);
        _setDelegationRatioRange(type(uint32).min, maximumDelegationRatio);
    }

    function register(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyValidProvision(indexer) whenNotPaused {
        (string memory url, string memory geohash, address rewardsDestination) = abi.decode(
            data,
            (string, string, address)
        );

        require(bytes(url).length > 0, SubgraphServiceEmptyUrl());
        require(indexers[indexer].registeredAt == 0, SubgraphServiceIndexerAlreadyRegistered());

        // Register the indexer
        indexers[indexer] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });
        if (rewardsDestination != address(0)) {
            _setRewardsDestination(indexer, rewardsDestination);
        }

        emit ServiceProviderRegistered(indexer);
    }

    function acceptProvision(
        address indexer,
        bytes calldata
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _checkProvisionTokens(indexer);
        _acceptProvisionParameters(indexer);
        emit ProvisionAccepted(indexer);
    }

    function startService(
        address indexer,
        bytes calldata data
    )
        external
        override
        onlyProvisionAuthorized(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        whenNotPaused
    {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof, maximumDelegationRatio);
        emit ServiceStarted(indexer);
    }

    function stopService(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        address allocationId = abi.decode(data, (address));
        _closeAllocation(allocationId);
        emit ServiceStopped(indexer);
    }

    function resizeAllocation(
        address indexer,
        address allocationId,
        uint256 tokens
    )
        external
        onlyProvisionAuthorized(indexer)
        onlyValidProvision(indexer)
        onlyRegisteredIndexer(indexer)
        whenNotPaused
    {
        _resizeAllocation(allocationId, tokens, maximumDelegationRatio);
    }

    function collect(
        address indexer,
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    ) external override onlyValidProvision(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        uint256 paymentCollected = 0;

        if (paymentType == IGraphPayments.PaymentTypes.QueryFee) {
            paymentCollected = _collectQueryFees(data);
        } else if (paymentType == IGraphPayments.PaymentTypes.IndexingRewards) {
            paymentCollected = _collectIndexingRewards(data);
        } else {
            revert SubgraphServiceInvalidPaymentType(paymentType);
        }

        emit ServicePaymentCollected(indexer, paymentType, paymentCollected);
    }

    function slash(address indexer, bytes calldata data) external override onlyDisputeManager whenNotPaused {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        _graphStaking().slash(indexer, tokens, reward, address(_disputeManager()));
        emit ServiceProviderSlashed(indexer, tokens);
    }

    function migrateLegacyAllocation(
        address indexer,
        address allocationId,
        bytes32 subgraphDeploymentID
    ) external onlyOwner {
        _migrateLegacyAllocation(indexer, allocationId, subgraphDeploymentID);
    }

    function setPauseGuardian(address pauseGuardian, bool allowed) external onlyOwner {
        _setPauseGuardian(pauseGuardian, allowed);
    }

    function getAllocation(address allocationId) external view override returns (Allocation.State memory) {
        return allocations[allocationId];
    }

    function getAllocationData(
        address allocationId
    ) external view override returns (address, bytes32, uint256, uint256) {
        Allocation.State memory allo = allocations[allocationId];
        return (
            allo.indexer,
            allo.subgraphDeploymentId,
            allo.tokens,
            allo.accRewardsPerAllocatedToken + allo.accRewardsPending
        );
    }

    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory) {
        return legacyAllocations[allocationId];
    }

    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32) {
        return _encodeAllocationProof(indexer, allocationId);
    }

    // -- Data service parameter getters --
    function _getThawingPeriodRange() internal view override returns (uint64 min, uint64 max) {
        uint64 disputePeriod = _disputeManager().getDisputePeriod();
        return (disputePeriod, type(uint64).max);
    }

    function _getVerifierCutRange() internal view override returns (uint32 min, uint32 max) {
        uint32 verifierCut = _disputeManager().getVerifierCut();
        return (verifierCut, type(uint32).max);
    }

    function _collectQueryFees(bytes memory _data) private returns (uint256 feesCollected) {
        ITAPCollector.SignedRAV memory signedRav = abi.decode(_data, (ITAPCollector.SignedRAV));
        address indexer = signedRav.rav.serviceProvider;
        address allocationId = abi.decode(signedRav.rav.metadata, (address));
        bytes32 subgraphDeploymentId = allocations.get(allocationId).subgraphDeploymentId;

        // release expired stake claims
        _releaseStake(IGraphPayments.PaymentTypes.QueryFee, indexer, 0);

        // Collect from GraphPayments
        PaymentCuts memory queryFeePaymentCuts = _getQueryFeePaymentCuts(subgraphDeploymentId);
        uint256 totalCut = queryFeePaymentCuts.serviceCut + queryFeePaymentCuts.curationCut;

        uint256 balanceBefore = _graphToken().balanceOf(address(this));
        uint256 tokensCollected = _tapCollector().collect(
            IGraphPayments.PaymentTypes.QueryFee,
            abi.encode(signedRav, totalCut)
        );
        uint256 tokensDataService = tokensCollected.mulPPM(totalCut);
        uint256 balanceAfter = _graphToken().balanceOf(address(this));
        require(
            balanceBefore + tokensDataService == balanceAfter,
            SubgraphServiceInconsistentCollection(balanceBefore, balanceAfter, tokensDataService)
        );

        uint256 tokensCurators = 0;
        uint256 tokensSubgraphService = 0;
        if (tokensCollected > 0) {
            // lock stake as economic security for fees
            uint256 tokensToLock = tokensCollected * stakeToFeesRatio;
            uint256 unlockTimestamp = block.timestamp + _disputeManager().getDisputePeriod();
            _lockStake(IGraphPayments.PaymentTypes.QueryFee, indexer, tokensToLock, unlockTimestamp);

            // calculate service and curator cuts
            tokensCurators = tokensCollected.mulPPMRoundUp(queryFeePaymentCuts.curationCut);
            tokensSubgraphService = tokensDataService - tokensCurators;

            if (tokensCurators > 0) {
                // curation collection changes subgraph signal so we take rewards snapshot
                _graphRewardsManager().onSubgraphSignalUpdate(subgraphDeploymentId);

                // Send GRT and bookkeep by calling collect()
                _graphToken().transfer(address(_curation()), tokensCurators);
                _curation().collect(subgraphDeploymentId, tokensCurators);
            }
        }

        emit QueryFeesCollected(indexer, tokensCollected, tokensCurators, tokensSubgraphService);
        return tokensCollected;
    }

    function _getQueryFeePaymentCuts(bytes32 _subgraphDeploymentId) private view returns (PaymentCuts memory) {
        PaymentCuts memory queryFeePaymentCuts = paymentCuts[IGraphPayments.PaymentTypes.QueryFee];

        // Only pay curation fees if the subgraph is curated
        if (!_curation().isCurated(_subgraphDeploymentId)) {
            queryFeePaymentCuts.curationCut = 0;
        }

        return queryFeePaymentCuts;
    }
}
