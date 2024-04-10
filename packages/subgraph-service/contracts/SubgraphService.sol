// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { ISubgraphDisputeManager } from "./interfaces/ISubgraphDisputeManager.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { GraphDataService } from "./data-service/GraphDataService.sol";
import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";
import { SubgraphServiceDirectory } from "./SubgraphServiceDirectory.sol";

// TODO: contract needs to be upgradeable and pausable
contract SubgraphService is
    EIP712,
    Ownable,
    GraphDataService,
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
    error SubgraphServiceInsufficientTokens(uint256 tokensAvailable, uint256 requiredTokensAvailable);
    error SubgraphServiceStakeClaimNotFound(bytes32 claimId);
    error SubgraphServiceCannotReleaseStake(uint256 tokensUsed, uint256 tokensClaim);
    error SubgraphServiceInvalidAllocationProof(address signer, address allocationId);

    event GraphContractsSet(address staking, address escrow, address payments);
    event DisputeManagerSet(address disputeManager);
    event TAPVerifierSet(address tapVerifier);
    event MinimumProvisionTokensSet(uint256 minimumProvisionTokens);
    event StakeLocked(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 unlockTimestamp);
    event StakeReleased(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 releaseAt);
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
        GraphDataService(_graphController)
        SubgraphServiceDirectory(_tapVerifier, _disputeManager)
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
        indexers[serviceProvider] = Indexer({
            registeredAt: block.timestamp,
            url: url,
            geoHash: geohash,
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
        _release(serviceProvider, 0);

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

        // do stake checks
        Indexer storage indexer = indexers[serviceProvider];
        uint256 tokensToLock = tokensToCollect * stakeToFeesRatio;
        uint256 requiredTokensAvailable = indexer.tokensUsed + tokensToLock;
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this));
        if (tokensAvailable < requiredTokensAvailable) {
            revert SubgraphServiceInsufficientTokens(tokensAvailable, requiredTokensAvailable);
        }

        // lock stake for economic security
        bytes32 claimId = _buildStakeClaimId(serviceProvider, indexer.stakeClaimNonce);
        uint256 unlockTimestamp = block.timestamp + disputeManager.getDisputePeriod();
        claims[claimId] = StakeClaim({
            indexer: serviceProvider,
            tokens: tokensToLock,
            createdAt: block.timestamp,
            releaseAt: unlockTimestamp,
            nextClaim: bytes32(0)
        });

        claims[indexer.stakeClaimTail].nextClaim = claimId;
        indexer.stakeClaimTail = claimId;
        indexer.stakeClaimNonce += 1;
        indexer.tokensUsed += tokensToLock;

        emit StakeLocked(serviceProvider, claimId, tokensToLock, unlockTimestamp);

        // call GraphPayments to collect fees
        tokensCollected[serviceProvider][payer] = tokens;
        graphPayments.collect(payer, serviceProvider, tokensToCollect);

        // TODO: distribute curation fees?!
        emit QueryFeesRedeemed(serviceProvider, payer, tokensToCollect);
    }

    // release tokens from a stake claim
    function release(address serviceProvider, uint256 amount) external override {
        _release(serviceProvider, amount);
    }

    /// @notice Release expired stake claims for a service provider
    /// @param n The number of stake claims to release, or 0 to release all
    function _release(address serviceProvider, uint256 n) internal {
        bool releaseAll = n == 0;

        // check the stake claims list
        bytes32 head = indexers[serviceProvider].stakeClaimHead;
        while (head != bytes32(0) && (releaseAll || n > 0)) {
            StakeClaim memory claim = _getStakeClaim(head);

            if (block.timestamp >= claim.releaseAt) {
                // Release stake
                Indexer storage indexer = indexers[serviceProvider];
                if (claim.tokens > indexer.tokensUsed) {
                    revert SubgraphServiceCannotReleaseStake(indexer.tokensUsed, claim.tokens);
                }
                indexer.tokensUsed -= claim.tokens;

                // Update list and refresh pointer
                indexer.stakeClaimHead = claim.nextClaim;
                delete claims[head];
                head = indexer.stakeClaimHead;
                if (!releaseAll) n--;

                emit StakeReleased(serviceProvider, indexer.stakeClaimHead, claim.tokens, claim.releaseAt);
            } else {
                break;
            }
        }
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

    function _getStakeClaim(bytes32 claimId) internal view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[claimId];
        if (claim.createdAt == 0) {
            revert SubgraphServiceStakeClaimNotFound(claimId);
        }
        return claim;
    }

    function _buildStakeClaimId(address serviceProvider, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), serviceProvider, nonce));
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
