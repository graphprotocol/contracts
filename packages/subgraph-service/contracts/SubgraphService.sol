// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ITAPVerifier } from "@graphprotocol/horizon/contracts/interfaces/ITAPVerifier.sol";
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
    ISubgraphService
{
    using PPMMath for uint256;
    using Allocation for mapping(address => Allocation.State);

    event QueryFeesRedeemed(
        address serviceProvider,
        address payer,
        uint256 tokensCollected,
        uint256 tokensCurators,
        uint256 tokensSubgraphService
    );

    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    error SubgraphServiceIndexerAlreadyRegistered();
    error SubgraphServiceIndexerNotRegistered(address indexer);
    error SubgraphServiceInconsistentCollection(uint256 tokensExpected, uint256 tokensCollected);

    modifier onlyRegisteredIndexer(address indexer) {
        if (indexers[indexer].registeredAt == 0) {
            revert SubgraphServiceIndexerNotRegistered(indexer);
        }
        _;
    }

    constructor(
        address graphController,
        address disputeManager,
        address tapVerifier,
        address curation,
        uint256 minimumProvisionTokens
    )
        Ownable(msg.sender)
        DataService(graphController)
        Directory(address(this), tapVerifier, disputeManager, curation)
        AllocationManager("SubgraphService", "1.0")
    {
        _setProvisionTokensRange(minimumProvisionTokens, type(uint256).max);
    }

    function register(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) whenNotPaused {
        (string memory url, string memory geohash, address rewardsDestination) = abi.decode(
            data,
            (string, string, address)
        );

        // Must provide a URL
        if (bytes(url).length == 0) {
            revert SubgraphServiceEmptyUrl();
        }

        // Only allow registering once
        if (indexers[indexer].registeredAt != 0) {
            revert SubgraphServiceIndexerAlreadyRegistered();
        }

        // Register the indexer
        indexers[indexer] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });

        if (rewardsDestination != address(0)) {
            _setRewardsDestination(indexer, rewardsDestination);
        }

        // Ensure the service provider created a valid provision for the data service
        // and accept it in the staking contract
        _acceptProvision(indexer);

        emit ServiceProviderRegistered(indexer);
    }

    function acceptProvision(
        address indexer,
        bytes calldata
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _acceptProvision(indexer);
    }

    function startService(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof, delegationRatio);
        emit ServiceStarted(indexer);
    }

    function collectServicePayment(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        (address allocationId, bytes32 poi) = abi.decode(data, (address, bytes32));
        uint256 rewards = _collectPOIRewards(allocationId, poi);
        emit ServicePaymentCollected(indexer, rewards);
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
    ) external onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _resizeAllocation(allocationId, tokens, delegationRatio);
    }

    // TODO: Does this design allow custom payment types?!
    function redeem(
        address indexer,
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external override onlyRegisteredIndexer(indexer) whenNotPaused {
        uint256 feesCollected = 0;

        if (feeType == IGraphPayments.PaymentTypes.QueryFee) {
            feesCollected = _redeemQueryFees(abi.decode(data, (ITAPVerifier.SignedRAV)));
        } else {
            revert SubgraphServiceInvalidPaymentType(feeType);
        }

        emit ServiceFeesRedeemed(indexer, feeType, feesCollected);
    }

    function slash(address indexer, bytes calldata data) external override onlyDisputeManager whenNotPaused {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        _graphStaking().slash(indexer, tokens, reward, address(DISPUTE_MANAGER));
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

    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory) {
        return legacyAllocations[allocationId];
    }

    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32) {
        return _encodeAllocationProof(indexer, allocationId);
    }

    // -- Data service parameter getters --
    function _getThawingPeriodRange() internal view override returns (uint64 min, uint64 max) {
        uint64 disputePeriod = DISPUTE_MANAGER.getDisputePeriod();
        return (disputePeriod, type(uint64).max);
    }

    function _getVerifierCutRange() internal view override returns (uint32 min, uint32 max) {
        uint32 verifierCut = DISPUTE_MANAGER.getVerifierCut();
        return (verifierCut, type(uint32).max);
    }

    function _redeemQueryFees(ITAPVerifier.SignedRAV memory _signedRAV) private returns (uint256 feesCollected) {
        address indexer = _signedRAV.rav.serviceProvider;
        address allocationId = abi.decode(_signedRAV.rav.metadata, (address));

        // release expired stake claims
        _releaseStake(IGraphPayments.PaymentTypes.QueryFee, indexer, 0);

        // validate RAV and calculate tokens to collect
        address payer = TAP_VERIFIER.verify(_signedRAV);
        uint256 tokens = _signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[indexer][payer];
        if (tokens <= tokensAlreadyCollected) {
            revert SubgraphServiceInconsistentRAVTokens(tokens, tokensAlreadyCollected);
        }
        uint256 tokensToCollect = tokens - tokensAlreadyCollected;
        uint256 tokensCurators = 0;
        uint256 tokensSubgraphService = 0;

        if (tokensToCollect > 0) {
            // lock stake as economic security for fees
            // block scope to avoid 'stack too deep' error
            {
                uint256 tokensToLock = tokensToCollect * stakeToFeesRatio;
                uint256 unlockTimestamp = block.timestamp + DISPUTE_MANAGER.getDisputePeriod();
                _lockStake(IGraphPayments.PaymentTypes.QueryFee, indexer, tokensToLock, unlockTimestamp);
            }

            // get subgraph deployment id - reverts if allocation is not found
            bytes32 subgraphDeploymentId = allocations.get(allocationId).subgraphDeploymentId;

            // calculate service and curator cuts
            // TODO: note we don't let curation cut round down to zero
            PaymentFee memory feePercentages = _getQueryFeesPaymentFees(subgraphDeploymentId);
            tokensSubgraphService = tokensToCollect.mulPPM(feePercentages.servicePercentage);
            tokensCurators = tokensToCollect.mulPPMRoundUp(feePercentages.curationPercentage);
            uint256 totalCut = tokensSubgraphService + tokensCurators;

            // collect fees
            uint256 balanceBefore = _graphToken().balanceOf(address(this));
            _graphPayments().collect(payer, indexer, tokensToCollect, IGraphPayments.PaymentTypes.QueryFee, totalCut);
            uint256 balanceAfter = _graphToken().balanceOf(address(this));
            if (balanceBefore + totalCut != balanceAfter) {
                revert SubgraphServiceInconsistentCollection(balanceBefore + totalCut, balanceAfter);
            }
            tokensCollected[indexer][payer] = tokens;

            // distribute curation cut to curators
            if (tokensCurators > 0) {
                // we are about to change subgraph signal so we take rewards snapshot
                _graphRewardsManager().onSubgraphSignalUpdate(subgraphDeploymentId);

                // Send GRT and bookkeep by calling collect()
                _graphToken().transfer(address(CURATION), tokensCurators);
                CURATION.collect(subgraphDeploymentId, tokensCurators);
            }
        }

        emit QueryFeesRedeemed(indexer, payer, tokensToCollect, tokensCurators, tokensSubgraphService);
        return tokensToCollect;
    }

    function _getQueryFeesPaymentFees(bytes32 _subgraphDeploymentId) private view returns (PaymentFee memory) {
        PaymentFee memory feePercentages = paymentFees[IGraphPayments.PaymentTypes.QueryFee];

        // Only pay curation fees if the subgraph is curated
        if (!CURATION.isCurated(_subgraphDeploymentId)) {
            feePercentages.curationPercentage = 0;
        }

        return feePercentages;
    }
}
