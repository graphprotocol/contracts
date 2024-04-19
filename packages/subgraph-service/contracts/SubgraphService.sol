// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

import { DataService } from "./data-service/DataService.sol";
import { IDataService } from "./data-service/IDataService.sol";
import { DataServiceOwnable } from "./data-service/extensions/DataServiceOwnable.sol";
import { DataServiceRescuable } from "./data-service/extensions/DataServiceRescuable.sol";
import { DataServiceFees } from "./data-service/extensions/DataServiceFees.sol";
import { ProvisionTracker } from "./data-service/libraries/ProvisionTracker.sol";

import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { Directory } from "./utilities/Directory.sol";
import { AllocationManager } from "./utilities/AllocationManager.sol";

import { PPMMath } from "./libraries/PPMMath.sol";
import { Allocation } from "./libraries/Allocation.sol";

// TODO: contract needs to be upgradeable and pausable
contract SubgraphService is
    DataService,
    DataServiceOwnable,
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

    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceAllocationAlreadyExists(address allocationId);
    error SubgraphServiceAllocationDoesNotExist(address allocationId);
    error SubgraphServiceAllocationClosed(address allocationId);
    error SubgraphServiceInvalidAllocationId();
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    error SubgraphServiceInvalidZeroPOI();
    error SubgraphSericeInvalidAllocationProof(address signer, address allocationId);

    event QueryFeesRedeemed(address serviceProvider, address payer, uint256 tokens);

    constructor(
        address _graphController,
        address _disputeManager,
        address _tapVerifier,
        uint256 _minimumProvisionTokens
    )
        DataService(_graphController)
        DataServiceOwnable(msg.sender)
        DataServiceRescuable()
        DataServiceFees()
        Directory(address(this), _tapVerifier, _disputeManager)
        AllocationManager("SubgraphService", "1.0")
    {
        _setProvisionTokensRange(_minimumProvisionTokens, type(uint256).max);
    }

    function register(address indexer, bytes calldata data) external override onlyProvisionAuthorized(indexer) {
        (string memory url, string memory geohash) = abi.decode(data, (string, string));

        // Must provide a URL
        if (bytes(url).length == 0) {
            revert SubgraphServiceEmptyUrl();
        }

        // Only allow registering once
        if (indexers[indexer].registeredAt != 0) {
            revert SubgraphServiceAlreadyRegistered();
        }

        // Register the indexer
        indexers[indexer] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });

        // Ensure the service provider created a valid provision for the data service
        // and accept it in the staking contract
        _checkProvisionParameters(indexer);
        _acceptProvision(indexer);
    }

    // TODO: Does this design allow custom payment types?!
    function redeem(
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external override returns (uint256 feesCollected) {
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
        releaseStake(IGraphPayments.PaymentTypes.QueryFee, serviceProvider, 0);

        // validate RAV and calculate tokens to collect
        address payer = tapVerifier.verify(signedRAV);
        uint256 tokens = signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[serviceProvider][payer];
        if (tokens <= tokensAlreadyCollected) {
            revert SubgraphServiceInconsistentRAVTokens(tokens, tokensAlreadyCollected);
        }
        uint256 tokensToCollect = tokens - tokensAlreadyCollected;

        // lock stake as economic security for fees
        uint256 tokensToLock = tokensToCollect * stakeToFeesRatio;
        uint256 unlockTimestamp = block.timestamp + disputeManager.getDisputePeriod();
        lockStake(IGraphPayments.PaymentTypes.QueryFee, serviceProvider, tokensToLock, unlockTimestamp);

        // collect fees
        tokensCollected[serviceProvider][payer] = tokens;
        uint256 subgraphServiceCut = tokensToCollect.mulPPM(feesCut);
        graphPayments.collect(payer, serviceProvider, tokensToCollect, feeType, subgraphServiceCut);

        // TODO: distribute curation fees, how?!
        emit QueryFeesRedeemed(serviceProvider, payer, tokensToCollect);
        return tokensToCollect;
    }

    function slash(
        address serviceProvider,
        bytes calldata data
    ) external override(DataServiceOwnable, IDataService) onlyDisputeManager {
        (uint256 tokens, uint256 reward) = abi.decode(data, (uint256, uint256));
        graphStaking.slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function startService(address indexer, bytes calldata data) external override onlyProvisionAuthorized(indexer) {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );
        _allocate(indexer, allocationId, subgraphDeploymentId, tokens, allocationProof);
    }

    function collectServicePayment(
        address indexer,
        bytes calldata data
    ) external override(DataService, IDataService) onlyProvisionAuthorized(indexer) {
        (address allocationId, bytes32 poi) = abi.decode(data, (address, bytes32));
        _collectPOIRewards(allocationId, poi);
    }

    function stopService(address indexer, bytes calldata data) external override onlyProvisionAuthorized(indexer) {
        address allocationId = abi.decode(data, (address));
        _closeAllocation(allocationId);
    }

    function resizeAllocation(
        address indexer,
        address allocationId,
        uint256 tokens
    ) external onlyProvisionAuthorized(indexer) {
        _resizeAllocation(allocationId, tokens);
    }

    function getAllocation(address allocationId) public view returns (Allocation.State memory) {
        return allocations.get(allocationId);
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
}
