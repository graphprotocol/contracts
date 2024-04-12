// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

import { DataService } from "./data-service/DataService.sol";
import { DataServiceOwnable } from "./data-service/extensions/DataServiceOwnable.sol";
import { DataServiceRescuable } from "./data-service/extensions/DataServiceRescuable.sol";
import { DataServiceFees } from "./data-service/extensions/DataServiceFees.sol";
import { ProvisionTracker } from "./data-service/utils/ProvisionTracker.sol";

import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";
import { Directory } from "./utils/Directory.sol";

// TODO: contract needs to be upgradeable and pausable
contract SubgraphService is
    EIP712,
    DataService,
    DataServiceOwnable,
    DataServiceRescuable,
    DataServiceFees,
    Directory,
    SubgraphServiceV1Storage,
    ISubgraphService
{
    using ProvisionTracker for mapping(address => uint256);

    uint256 private immutable MAX_PPM = 1000000; // 100% in parts per million
    bytes32 private immutable EIP712_ALLOCATION_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");
    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceInvalidAllocationProof(address signer, address allocationId);
    error SubgraphServiceAllocationAlreadyExists(address allocationId);
    error SubgraphServiceInvalidZeroAllocationId();
    error SubgraphServiceAllocateInsufficientTokens(uint256 available, uint256 required);
    error SubgraphServiceInvalidPaymentType(IGraphPayments.PaymentTypes feeType);
    event QueryFeesRedeemed(address serviceProvider, address payer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphDeploymentID`
     * during `epoch`.
     * `allocationID` indexer derived address used to identify the allocation.
     * `metadata` additional information related to the allocation.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentId,
        uint256 epoch,
        uint256 tokens,
        address indexed allocationId
    );

    constructor(
        string memory eip712Name,
        string memory eip712Version,
        address _graphController,
        address _disputeManager,
        address _tapVerifier,
        uint256 _minimumProvisionTokens
    )
        EIP712(eip712Name, eip712Version)
        DataService(_graphController)
        DataServiceOwnable(msg.sender)
        DataServiceRescuable()
        DataServiceFees()
        Directory(address(this), _tapVerifier, _disputeManager)
    {
        _setProvisionTokensRange(_minimumProvisionTokens, type(uint256).max);
    }

    function register(
        address serviceProvider,
        bytes calldata data
    ) external override onlyProvisionAuthorized(serviceProvider) {
        (string memory url, string memory geohash) = abi.decode(data, (string, string));

        // Must provide a URL
        if (bytes(url).length == 0) {
            revert SubgraphServiceEmptyUrl();
        }

        // Only allow registering once
        if (indexers[serviceProvider].registeredAt != 0) {
            revert SubgraphServiceAlreadyRegistered();
        }

        // Ensure the service provider created a valid provision for the data service
        _checkProvision(serviceProvider);

        // Register the indexer
        indexers[serviceProvider] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });

        // Accept provision in staking contract
        graphStaking.acceptProvision(serviceProvider);
    }

    function redeem(
        IGraphPayments.PaymentTypes feeType,
        bytes calldata data
    ) external override returns (uint256 feesCollected) {
        if (feeType == IGraphPayments.PaymentTypes.QueryFee) {
            feesCollected = _redeemQueryFees(abi.decode(data, (ITAPVerifier.SignedRAV)));
        } else {
            revert SubgraphServiceInvalidPaymentType(feeType);
        }
    }

    function _redeemQueryFees(ITAPVerifier.SignedRAV memory signedRAV) internal returns (uint256 feesCollected) {
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
        // TODO: update payment type here with the correct value, is it maybe a parameter?
        uint256 subgraphServiceCut = (tokensToCollect * feesCut) / MAX_PPM;
        graphPayments.collect(payer, serviceProvider, tokensToCollect, 0, subgraphServiceCut);

        // TODO: distribute curation fees, how?!
        emit QueryFeesRedeemed(serviceProvider, payer, tokensToCollect);
        return tokensToCollect;
    }

    function slash(address serviceProvider, uint256 tokens, uint256 reward) external override onlyDisputeManager {
        graphStaking.slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function allocate(
        address indexer,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        address allocationId,
        bytes calldata proof
    ) external override onlyProvisionAuthorized(indexer) {
        if (allocationId == address(0)) {
            revert SubgraphServiceInvalidZeroAllocationId();
        }

        if (allocations[allocationId].createdAt != 0) {
            revert SubgraphServiceAllocationAlreadyExists(allocationId);
        }

        // Caller must prove that they own the private key for the allocationId address
        // The proof is an EIP712 signed message of (indexer,allocationId)
        bytes32 digest = encodeProof(indexer, allocationId);
        address signer = ECDSA.recover(digest, proof);
        if (signer != allocationId) {
            revert SubgraphServiceInvalidAllocationProof(signer, allocationId);
        }

        // Check that the indexer has enough tokens available
        provisionTrackerAllocations.lock(graphStaking, indexer, tokens);

        Allocation memory allocation = Allocation({
            indexer: indexer,
            subgraphDeploymentId: subgraphDeploymentId,
            tokens: tokens,
            createdAt: block.timestamp,
            closedAt: 0,
            accRewardsPerAllocatedToken: 0
        });
        allocations[allocationId] = allocation;

        if (tokens > 0) {
            // TODO: update subgraphAllocations for rewards
        }

        emit AllocationCreated(indexer, subgraphDeploymentId, allocation.createdAt, allocation.tokens, allocationId);
    }

    function getAllocation(address allocationId) external view returns (Allocation memory) {
        return allocations[allocationId];
    }

    function encodeProof(address indexer, address allocationId) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EIP712_ALLOCATION_PROOF_TYPEHASH, indexer, allocationId)));
    }

    function _getThawingPeriodRange() internal view override returns (uint64 min, uint64 max) {
        uint64 disputePeriod = disputeManager.getDisputePeriod();
        return (disputePeriod, type(uint64).max);
    }

    function _getVerifierCutRange() internal view override returns (uint32 min, uint32 max) {
        uint32 verifierCut = disputeManager.getVerifierCut();
        return (verifierCut, type(uint32).max);
    }
}
