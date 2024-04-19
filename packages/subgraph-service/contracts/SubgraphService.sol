// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

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

import { PPMMath } from "./libraries/PPMMath.sol";

import { Directory } from "./utilities/Directory.sol";
import { Allocation } from "./libraries/Allocation.sol";

// TODO: contract needs to be upgradeable and pausable
contract SubgraphService is
    DataService,
    DataServiceOwnable,
    DataServiceRescuable,
    DataServiceFees,
    Directory,
    EIP712,
    SubgraphServiceV1Storage,
    ISubgraphService
{
    using PPMMath for uint256;
    using ProvisionTracker for mapping(address => uint256);
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;

    bytes32 private immutable EIP712_ALLOCATION_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceInvalidAllocationProof(address signer, address allocationId);
    error SubgraphServiceAllocationAlreadyExists(address allocationId);
    error SubgraphServiceAllocationDoesNotExist(address allocationId);
    error SubgraphServiceAllocationClosed(address allocationId);
    error SubgraphServiceInvalidAllocationId();
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    error SubgraphServiceZeroTokensAllocation(address allocationId);
    error SubgraphServiceInvalidZeroPOI();
    error SubgraphSericeInvalidAllocationProof(address signer, address allocationId);

    event QueryFeesRedeemed(address serviceProvider, address payer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphDeploymentId`
     * during `epoch`.
     * `allocationId` indexer derived address used to identify the allocation.
     */
    event AllocationCreated(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
    );

    event AllocationCollected(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokensRewards,
        uint256 tokensIndexerRewards,
        uint256 tokensDelegationRewards
    );

    event AllocationResized(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 newTokens,
        uint256 oldTokens
    );

    /**
     * @dev Emitted when `indexer` closes an allocation with id `allocationId`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentId`.
     */
    event AllocationClosed(
        address indexed indexer,
        address indexed allocationId,
        bytes32 indexed subgraphDeploymentId,
        uint256 tokens
    );

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
        EIP712("SubgraphService", "1.0")
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
        _slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function startService(address indexer, bytes calldata data) external override onlyProvisionAuthorized(indexer) {
        (bytes32 subgraphDeploymentId, uint256 tokens, address allocationId, bytes memory allocationProof) = abi.decode(
            data,
            (bytes32, uint256, address, bytes)
        );

        if (allocationId == address(0)) revert SubgraphServiceInvalidAllocationId();

        _verifyAllocationProof(indexer, allocationId, allocationProof);

        uint256 accRewardsPerAllocatedToken = tokens > 0
            ? graphRewardsManager.onSubgraphAllocationUpdate(subgraphDeploymentId)
            : 0;
        Allocation.State memory allocation = allocations.create(
            indexer,
            allocationId,
            subgraphDeploymentId,
            tokens,
            accRewardsPerAllocatedToken
        );

        // Check that the indexer has enough tokens available
        provisionTrackerAllocations.lock(graphStaking, indexer, tokens);

        if (tokens > 0) {
            subgraphAllocations[allocation.subgraphDeploymentId] =
                subgraphAllocations[allocation.subgraphDeploymentId] +
                allocation.tokens;
        }

        emit AllocationCreated(indexer, allocationId, subgraphDeploymentId, allocation.tokens);
    }

    function collectServicePayment(
        address indexer,
        bytes calldata data
    ) external override(DataService, IDataService) onlyProvisionAuthorized(indexer) {
        (address allocationId, bytes32 poi) = abi.decode(data, (address, bytes32));

        if (poi == bytes32(0)) revert SubgraphServiceInvalidZeroPOI();

        Allocation.State memory allocation = allocations.get(allocationId);
        if (!allocation.isOpen()) revert SubgraphServiceAllocationClosed(allocationId);
        if (allocation.isAltruistic()) revert SubgraphServiceZeroTokensAllocation(allocationId);

        // Mint indexing rewards
        uint256 timeSinceLastPOI = block.number - allocation.lastPOIPresentedAt;
        uint256 tokensRewards = timeSinceLastPOI <= maxPOIStaleness ? graphRewardsManager.takeRewards(allocationId) : 0;

        // Update POI timestamp and take rewards snapshot
        // For stale POIs this ensures the rewards are not collected with the next valid POI
        allocations.presentPOI(
            allocationId,
            graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );

        if (tokensRewards == 0) {
            return;
        }

        // Distribute rewards to delegators
        // TODO: remove the uint8 cast when PRs are merged
        uint256 delegatorCut = graphStaking.getDelegationCut(indexer, uint8(IGraphPayments.PaymentTypes.IndexingFee));
        uint256 tokensDelegationRewards = tokensRewards.mulPPM(delegatorCut);
        graphToken.approve(address(graphStaking), tokensDelegationRewards);
        graphStaking.addToDelegationPool(indexer, tokensDelegationRewards);

        // Distribute rewards to indexer
        uint256 tokensIndexerRewards = tokensRewards - tokensDelegationRewards;
        address rewardsDestination = rewardsDestination[indexer];
        if (rewardsDestination == address(0)) {
            graphToken.approve(address(graphStaking), tokensIndexerRewards);
            graphStaking.stakeToProvision(indexer, address(this), tokensIndexerRewards);
        } else {
            graphToken.transfer(rewardsDestination, tokensIndexerRewards);
        }

        emit AllocationCollected(
            indexer,
            allocationId,
            allocation.subgraphDeploymentId,
            tokensRewards,
            tokensIndexerRewards,
            tokensDelegationRewards
        );
    }

    function stopService(address indexer, bytes calldata data) external override onlyProvisionAuthorized(indexer) {
        address allocationId = abi.decode(data, (address));

        Allocation.State memory allocation = getAllocation(allocationId);

        allocations.close(
            allocationId,
            graphRewardsManager.onSubgraphAllocationUpdate(allocation.subgraphDeploymentId)
        );
        provisionTrackerAllocations.release(indexer, allocation.tokens);

        allocations[allocationId].accRewardsPerAllocatedToken = subgraphAllocations[allocation.subgraphDeploymentId] =
            subgraphAllocations[allocation.subgraphDeploymentId] -
            allocation.tokens;

        emit AllocationClosed(allocation.indexer, allocationId, allocation.subgraphDeploymentId, allocation.tokens);
    }

    function resizeAllocation(
        address indexer,
        address allocationId,
        uint256 tokens
    ) external onlyProvisionAuthorized(indexer) {
        Allocation.State memory allocation = getAllocation(allocationId);

        // Exit early if the allocation size is not changing
        if (tokens == allocation.tokens) {
            return;
        }

        // Update the allocation
        uint256 oldTokens = allocation.tokens;
        allocations[allocationId].tokens = tokens;

        // Update provision tracker
        if (tokens > oldTokens) {
            provisionTrackerAllocations.lock(graphStaking, allocation.indexer, tokens - oldTokens);
        } else {
            provisionTrackerAllocations.release(allocation.indexer, oldTokens - tokens);
        }

        // Take rewards snapshot for the subgraph before updating the subgraph allocated tokens
        allocations[allocationId].accRewardsPerAllocatedToken = graphRewardsManager.onSubgraphAllocationUpdate(
            allocation.subgraphDeploymentId
        );
        subgraphAllocations[allocation.subgraphDeploymentId] =
            subgraphAllocations[allocation.subgraphDeploymentId] +
            (tokens - oldTokens);

        emit AllocationResized(allocation.indexer, allocationId, allocation.subgraphDeploymentId, tokens, oldTokens);
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

    // -- Allocation Proof Verification --
    function _verifyAllocationProof(address indexer, address allocationId, bytes memory proof) internal view {
        bytes32 digest = _encodeAllocationProof(indexer, allocationId);
        address signer = ECDSA.recover(digest, proof);
        if (signer != allocationId) revert SubgraphSericeInvalidAllocationProof(signer, allocationId);
    }

    function _encodeAllocationProof(address indexer, address allocationId) internal view returns (bytes32) {
        return EIP712._hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_PROOF_TYPEHASH, indexer, allocationId)));
    }
}
