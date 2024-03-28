// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IGraphEscrow } from "./interfaces/IGraphEscrow.sol";
import { IGraphPayments } from "./interfaces/IGraphPayments.sol";

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { SubgraphServiceV1Storage } from "./SubgraphServiceStorage.sol";

abstract contract SubgraphService is Ownable(msg.sender), SubgraphServiceV1Storage, ISubgraphService {
    error SubgraphServiceNotAuthorized(address caller, address serviceProvider, address service);
    error SubgraphServiceNotDisputeManager(address caller, address disputeManager);
    error SubgraphServiceAlreadyRegistered();
    error SubgraphServiceEmptyUrl();
    error SubgraphServiceProvisionNotFound(address serviceProvider, address service);
    error SubgraphServiceInvalidProvisionVerifierCut(uint256 verifierCut, uint256 maxVerifierCut);
    error SubgraphServiceInvalidProvisionTokens(uint256 tokens, uint256 minimumProvisionTokens);
    error SubgraphServiceInvalidProvisionThawingPeriod(uint64 thawingPeriod, uint64 disputePeriod);
    error SubgraphServiceInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);
    error SubgraphServiceInsufficientTokens(uint256 tokensAvailable, uint256 requiredTokensAvailable);
    error SubgraphServiceStakeClaimNotFound(bytes32 claimId);
    error SubgraphServiceCannotReleaseStake(uint256 tokensUsed, uint256 tokensClaim);

    event GraphContractsSet(address staking, address escrow, address payments);
    event DisputeManagerSet(address disputeManager);
    event TAPVerifierSet(address tapVerifier);
    event MinimumProvisionTokensSet(uint256 minimumProvisionTokens);
    event StakeReleased(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 releaseAt);

    modifier onlyAuthorized(address serviceProvider) {
        if (!staking.isAuthorized(msg.sender, serviceProvider, address(this))) {
            revert SubgraphServiceNotAuthorized(msg.sender, serviceProvider, address(this));
        }
        _;
    }

    modifier onlyDisputeManager() {
        if (msg.sender != address(disputeManager)) {
            revert SubgraphServiceNotDisputeManager(msg.sender, address(disputeManager));
        }
        _;
    }

    constructor(
        address _staking,
        address _escrow,
        address _payments,
        address _disputeManager,
        address _tapVerifier,
        uint256 _minimumProvisionTokens
    ) {
        // TODO: some address validation here, not zero, etc
        staking = IHorizonStaking(_staking);
        escrow = IGraphEscrow(_escrow);
        payments = IGraphPayments(_payments);
        emit GraphContractsSet(_staking, _escrow, _payments);

        _setDisputeManager(_disputeManager);
        _setTAPVerifier(_tapVerifier);
        _setMinimumProvisionTokens(_minimumProvisionTokens);
    }

    // TODO: implement provisionAndRegister convenience method
    function register(
        address serviceProvider,
        string calldata url,
        string calldata geohash
    ) external override onlyAuthorized(serviceProvider) {
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
    }

    function redeem(ITAPVerifier.SignedRAV calldata signedRAV) external override returns (uint256 queryFees) {
        // check the stake claims list
        address serviceProvider = signedRAV.rav.serviceProvider;
        _release(serviceProvider, 0);

        // post rav to tap verifier
        address signer = tapVerifier.verify(signedRAV);
        address payer = escrow.getSender(signer);

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
        uint256 tokensAvailable = staking.getTokensAvailable(serviceProvider, address(this));
        if (tokensAvailable < requiredTokensAvailable) {
            revert SubgraphServiceInsufficientTokens(tokensAvailable, requiredTokensAvailable);
        }

        // lock stake for economic security
        bytes32 claimId = _buildStakeClaimId(serviceProvider, indexer.stakeClaimNonce);
        claims[claimId] = StakeClaim({
            indexer: serviceProvider,
            tokens: tokensToLock,
            createdAt: block.timestamp,
            releaseAt: block.timestamp + disputeManager.getDisputePeriod(),
            nextClaim: bytes32(0)
        });

        claims[indexer.stakeClaimTail].nextClaim = claimId;
        indexer.stakeClaimTail = claimId;
        indexer.stakeClaimNonce += 1;
        indexer.tokensUsed += tokensToLock;

        // call GraphPayments to collect fees
        tokensCollected[serviceProvider][payer] = tokens;
        payments.collect(payer, serviceProvider, tokensToCollect);
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
        staking.slash(serviceProvider, tokens, reward, address(disputeManager));
    }

    function setDisputeManager(address _disputeManager) external onlyOwner {
        _setDisputeManager(_disputeManager);
    }

    function setMinimumProvisionTokens(uint256 _minimumProvisionTokens) external onlyOwner {
        _setMinimumProvisionTokens(_minimumProvisionTokens);
    }

    function setTAPVerifier(address _tapVerifier) external onlyOwner {
        _setTAPVerifier(_tapVerifier);
    }

    function _setDisputeManager(address _disputeManager) internal {
        disputeManager = IDisputeManager(_disputeManager);
        emit DisputeManagerSet(_disputeManager);
    }

    function _setTAPVerifier(address _tapVerifier) internal {
        tapVerifier = ITAPVerifier(_tapVerifier);
        emit TAPVerifierSet(_tapVerifier);
    }

    function _setMinimumProvisionTokens(uint256 _minimumProvisionTokens) internal {
        minimumProvisionTokens = _minimumProvisionTokens;
        emit MinimumProvisionTokensSet(minimumProvisionTokens);
    }

    function _getProvision(address serviceProvider) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = staking.getProvision(serviceProvider, address(this));
        if (provision.createdAt == 0) {
            revert SubgraphServiceProvisionNotFound(serviceProvider, address(this));
        }
        return provision;
    }

    function _getStakeClaim(bytes32 claimId) internal view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[claimId];
        if (claim.createdAt == 0) {
            revert SubgraphServiceStakeClaimNotFound(claimId);
        }
        return claim;
    }
    /// @notice Checks if the service provider has a valid provision for the data service in the staking contract
    /// @param serviceProvider The address of the service provider
    function _checkProvision(address serviceProvider) internal view {
        IHorizonStaking.Provision memory provision = _getProvision(serviceProvider);

        // Ensure the provision meets the data service requirements
        // ... it allows taking the verifier cut
        uint256 verifierCut = disputeManager.getVerifierCut();
        if (provision.maxVerifierCut >= verifierCut) {
            revert SubgraphServiceInvalidProvisionVerifierCut(verifierCut, provision.maxVerifierCut);
        }

        // ... it has enough stake
        if (provision.tokens < minimumProvisionTokens) {
            revert SubgraphServiceInvalidProvisionTokens(provision.tokens, minimumProvisionTokens);
        }

        // ... it allows enough time for dispute resolution before service provider can withdraw funds
        uint64 disputePeriod = disputeManager.getDisputePeriod();
        if (provision.thawingPeriod >= disputePeriod) {
            revert SubgraphServiceInvalidProvisionThawingPeriod(provision.thawingPeriod, disputePeriod);
        }
    }

    function _buildStakeClaimId(address serviceProvider, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), serviceProvider, nonce));
    }
}
