// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ISubgraphDisputeManager } from "./interfaces/ISubgraphDisputeManager.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { DataServiceFees } from "./data-service/extensions/DataServiceFees.sol";
import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { SubgraphServiceDirectory } from "./SubgraphServiceDirectory.sol";

// TODO: contract needs to be upgradeable and pausable
contract SubgraphService is
    EIP712,
    Ownable,
    DataServiceFees,
    SubgraphServiceDirectory,
    SubgraphServiceV1Storage,
    ISubgraphService
{
    // --- EIP 712 ---
    bytes32 private immutable ALLOCATION_PROOF_TYPEHASH =
        keccak256("AllocationIdProof(address indexer,address allocationId)");

    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceInvalidAllocationProof(address signer, address allocationId);

    event QueryFeesRedeemed(address serviceProvider, address payer, uint256 tokens);

    constructor(
        string memory name,
        string memory version,
        address _graphController,
        address _disputeManager,
        address _tapVerifier,
        uint256 _minimumProvisionTokens
    )
        EIP712(name, version)
        Ownable(msg.sender)
        DataServiceFees(_graphController)
        SubgraphServiceDirectory(address(this), _tapVerifier, _disputeManager)
    {
        _setProvisionTokensRange(_minimumProvisionTokens, type(uint256).max);
    }

    // TODO: implement provisionAndRegister convenience method
    function register(
        address serviceProvider,
        string calldata url,
        string calldata geohash
    ) external override onlyProvisionAuthorized(serviceProvider) {
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

        // TODO: save delegator cut parameters
        // Register the service provider
        indexers[serviceProvider] = Indexer({ registeredAt: block.timestamp, url: url, geoHash: geohash });
        feesServiceProviders[serviceProvider] = FeesServiceProvider({
            tokensUsed: 0,
            stakeClaimHead: bytes32(0),
            stakeClaimTail: bytes32(0),
            stakeClaimNonce: 0
        });

        // Accept provision in staking contract
        graphStaking.acceptProvision(serviceProvider);
    }

    function redeem(ITAPVerifier.SignedRAV calldata signedRAV) external override returns (uint256 queryFees) {
        // check the stake claims list
        address serviceProvider = signedRAV.rav.serviceProvider;
        releaseStake(serviceProvider, 0);

        // post rav to tap verifier
        address signer = tapVerifier.verify(signedRAV);
        address payer = graphEscrow.getSender(signer);

        // calculate delta
        uint256 tokens = signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[serviceProvider][payer];
        if (tokens <= tokensAlreadyCollected) {
            revert SubgraphServiceInconsistentRAVTokens(tokens, tokensAlreadyCollected);
        }
        uint256 tokensToCollect = tokens - tokensAlreadyCollected;

        uint256 tokensToLock = tokensToCollect * stakeToFeesRatio;
        uint256 unlockTimestamp = block.timestamp + disputeManager.getDisputePeriod();
        lockStake(serviceProvider, tokensToLock, unlockTimestamp);

        // call GraphPayments to collect fees
        tokensCollected[serviceProvider][payer] = tokens;
        graphPayments.collect(payer, serviceProvider, tokensToCollect);

        // TODO: distribute curation fees?!
        emit QueryFeesRedeemed(serviceProvider, payer, tokensToCollect);
    }

    function slash(address serviceProvider, uint256 tokens, uint256 reward) external override onlyDisputeManager {
        graphStaking.slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function allocate(
        address indexer,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        address allocationId,
        bytes32 metadata,
        bytes calldata proof
    ) external override onlyProvisionAuthorized(indexer) {
        // Caller must prove that they own the private key for the allocationId address
        // The proof is an EIP712 signed message of (indexer,allocationId)
        bytes32 digest = encodeProof(indexer, allocationId);
        address signer = ECDSA.recover(digest, proof);
        if (signer != allocationId) {
            revert SubgraphServiceInvalidAllocationProof(signer, allocationId);
        }

        Allocation memory allocation = ISubgraphService.Allocation({
            indexer: indexer,
            subgraphDeploymentID: subgraphDeploymentId,
            tokens: tokens,
            createdAt: block.timestamp,
            closedAt: 0,
            accRewardsPerAllocatedToken: 0
        });
        allocations[allocationId] = allocation;
    }

    function getAllocation(address allocationId) external view returns (Allocation memory) {
        return allocations[allocationId];
    }

    function encodeProof(address indexer, address allocationId) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(ALLOCATION_PROOF_TYPEHASH, indexer, allocationId)));
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
