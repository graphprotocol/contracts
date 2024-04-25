// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

import { DataService } from "./data-service/DataService.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DataServiceRescuable } from "./data-service/extensions/DataServiceRescuable.sol";
import { DataServicePausable } from "./data-service/extensions/DataServicePausable.sol";
import { DataServiceFees } from "./data-service/extensions/DataServiceFees.sol";

import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { Directory } from "./utilities/Directory.sol";
import { AllocationManager } from "./utilities/AllocationManager.sol";

import { PPMMath } from "./data-service/libraries/PPMMath.sol";
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
    using Allocation for Allocation.State;

    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceAllocationAlreadyExists(address allocationId);
    error SubgraphServiceAllocationDoesNotExist(address allocationId);
    error SubgraphServiceAllocationClosed(address allocationId);
    error SubgraphServiceInvalidAllocationId();
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    error SubgraphServiceInvalidZeroPOI();
    error SubgraphServiceInvalidAllocationProof(address signer, address allocationId);
    error SubgraphServiceIndexerAlreadyRegistered();
    error SubgraphServiceIndexerNotRegistered(address indexer);

    event QueryFeesRedeemed(address serviceProvider, address payer, uint256 tokens);

    constructor(
        address _graphController,
        address _disputeManager,
        address _tapVerifier,
        address _curation,
        uint256 _minimumProvisionTokens
    )
        Ownable(msg.sender)
        DataService(_graphController)
        Directory(address(this), _tapVerifier, _disputeManager, _curation)
        AllocationManager("SubgraphService", "1.0")
    {
        _setProvisionTokensRange(_minimumProvisionTokens, type(uint256).max);
    }

    modifier onlyRegisteredIndexer(address indexer) {
        if (indexers[indexer].registeredAt == 0) {
            revert SubgraphServiceIndexerNotRegistered(indexer);
        }
        _;
    }

    function register(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) whenNotPaused {
        (string memory url, string memory geohash) = abi.decode(data, (string, string));

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

        // Ensure the service provider created a valid provision for the data service
        // and accept it in the staking contract
        _acceptProvision(indexer);
    }

    function acceptProvision(
        address indexer,
        bytes calldata
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _acceptProvision(indexer);
    }

    // TODO: Does this design allow custom payment types?!
    function redeem(
        address indexer,
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external override onlyRegisteredIndexer(indexer) whenNotPaused returns (uint256 feesCollected) {
        if (feeType == IGraphPayments.PaymentTypes.QueryFee) {
            feesCollected = _redeemQueryFees(feeType, abi.decode(data, (ITAPVerifier.SignedRAV)));
        } else {
            revert SubgraphServiceInvalidPaymentType(feeType);
        }
    }

    function _redeemQueryFees(
        IGraphPayments.PaymentTypes feeType,
        ITAPVerifier.SignedRAV memory signedRAV
    ) internal returns (uint256 feesCollected) {
        address serviceProvider = signedRAV.rav.serviceProvider;

        // release expired stake claims
        _releaseStake(IGraphPayments.PaymentTypes.QueryFee, serviceProvider, 0);

        // validate RAV and calculate tokens to collect
        address payer = tapVerifier.verify(signedRAV);
        uint256 tokens = signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[serviceProvider][payer];
        if (tokens <= tokensAlreadyCollected) {
            revert SubgraphServiceInconsistentRAVTokens(tokens, tokensAlreadyCollected);
        }
        uint256 tokensToCollect = tokens - tokensAlreadyCollected;

        if (tokensToCollect > 0) {
            // lock stake as economic security for fees
            uint256 tokensToLock = tokensToCollect * stakeToFeesRatio;
            uint256 unlockTimestamp = block.timestamp + disputeManager.getDisputePeriod();
            _lockStake(IGraphPayments.PaymentTypes.QueryFee, serviceProvider, tokensToLock, unlockTimestamp);

            // collect fees
            tokensCollected[serviceProvider][payer] = tokens;
            uint256 subgraphServiceCut = tokensToCollect.mulPPM(feesCut);
            graphPayments.collect(payer, serviceProvider, tokensToCollect, feeType, subgraphServiceCut);

            // TODO: distribute curation fees, how?!
            // _distributeCurationFees(signedRAV.rav.subgraphDeploymentID, tokensToCollect, signedRAV.rav.curationPercentage);
        }

        emit QueryFeesRedeemed(serviceProvider, payer, tokensToCollect);
        return tokensToCollect;
    }

    function slash(address indexer, bytes calldata data) external override onlyDisputeManager whenNotPaused {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        graphStaking.slash(indexer, tokens, reward, address(disputeManager));
    }

    function startService(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof);
    }

    function collectServicePayment(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        (address allocationId, bytes32 poi) = abi.decode(data, (address, bytes32));
        _collectPOIRewards(allocationId, poi);
    }

    function stopService(
        address indexer,
        bytes calldata data
    ) external override onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        address allocationId = abi.decode(data, (address));
        _closeAllocation(allocationId);
    }

    function resizeAllocation(
        address indexer,
        address allocationId,
        uint256 tokens
    ) external onlyProvisionAuthorized(indexer) onlyRegisteredIndexer(indexer) whenNotPaused {
        _resizeAllocation(allocationId, tokens);
    }

    function getAllocation(address allocationId) external view override returns (Allocation.State memory) {
        return allocations[allocationId];
    }

    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory) {
        return legacyAllocations[allocationId];
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

    // -- Data service parameter getters --
    function _getThawingPeriodRange() internal view override returns (uint64 min, uint64 max) {
        uint64 disputePeriod = disputeManager.getDisputePeriod();
        return (disputePeriod, type(uint64).max);
    }

    function _getVerifierCutRange() internal view override returns (uint32 min, uint32 max) {
        uint32 verifierCut = disputeManager.getVerifierCut();
        return (verifierCut, type(uint32).max);
    }

    function _distributeCurationFees(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        uint256 _curationPercentage
    ) private returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }

        bool isCurationEnabled = _curationPercentage > 0 && address(curation) != address(0);

        if (isCurationEnabled && curation.isCurated(_subgraphDeploymentID)) {
            // Calculate the tokens after curation fees first, and subtact that,
            // to prevent curation fees from rounding down to zero
            uint256 tokensAfterCurationFees = (PPMMath.MAX_PPM - _curationPercentage).mulPPM(_tokens);
            uint256 curationFees = _tokens - tokensAfterCurationFees;
            if (curationFees > 0) {
                // we are about to change subgraph signal so we take rewards snapshot
                graphRewardsManager.onSubgraphSignalUpdate(_subgraphDeploymentID);

                // Send GRT and bookkeep by calling collect()
                graphToken.transfer(address(curation), curationFees);
                curation.collect(_subgraphDeploymentID, curationFees);
            }
            return curationFees;
        }
        return 0;
    }
}
