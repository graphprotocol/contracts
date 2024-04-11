// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { DataService } from "../DataService.sol";
import { DataServiceFeesV1Storage } from "./DataServiceFeesStorage.sol";
import { IDataServiceFees } from "./IDataServiceFees.sol";

abstract contract DataServiceFees is DataService, DataServiceFeesV1Storage, IDataServiceFees {
    error GDSFeesClaimNotFound(bytes32 claimId);
    error GDSFeesInsufficientTokens(uint256 available, uint256 required);
    error GDSFeesCannotReleaseStake(uint256 tokensUsed, uint256 tokensClaim);

    event StakeLocked(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 unlockTimestamp);
    event StakeReleased(address serviceProvider, bytes32 claimId, uint256 tokens, uint256 releaseAt);

    constructor(address _controller) DataService(_controller) {}

    function lockStake(address serviceProvider, uint256 tokens, uint256 unlockTimestamp) internal {
        // do stake checks
        FeesServiceProvider storage serviceProviderDetails = feesServiceProviders[serviceProvider];
        uint256 requiredTokensAvailable = serviceProviderDetails.tokensUsed + tokens;
        uint256 tokensAvailable = graphStaking.getTokensAvailable(serviceProvider, address(this));
        if (tokensAvailable < requiredTokensAvailable) {
            revert GDSFeesInsufficientTokens(tokensAvailable, requiredTokensAvailable);
        }

        // lock stake for economic security
        bytes32 claimId = _buildStakeClaimId(serviceProvider, serviceProviderDetails.stakeClaimNonce);
        claims[claimId] = StakeClaim({
            indexer: serviceProvider,
            tokens: tokens,
            createdAt: block.timestamp,
            releaseAt: unlockTimestamp,
            nextClaim: bytes32(0)
        });

        claims[serviceProviderDetails.stakeClaimTail].nextClaim = claimId;
        serviceProviderDetails.stakeClaimTail = claimId;
        serviceProviderDetails.stakeClaimNonce += 1;
        serviceProviderDetails.tokensUsed += tokens;

        emit StakeLocked(serviceProvider, claimId, tokens, unlockTimestamp);
    }

    /// @notice Release expired stake claims for a service provider
    /// @param n The number of stake claims to release, or 0 to release all
    function releaseStake(address serviceProvider, uint256 n) public {
        bool releaseAll = n == 0;

        // check the stake claims list
        bytes32 head = feesServiceProviders[serviceProvider].stakeClaimHead;
        while (head != bytes32(0) && (releaseAll || n > 0)) {
            StakeClaim memory claim = _getStakeClaim(head);

            if (block.timestamp >= claim.releaseAt) {
                // Release stake
                FeesServiceProvider storage serviceProviderDetails = feesServiceProviders[serviceProvider];
                if (claim.tokens > serviceProviderDetails.tokensUsed) {
                    revert GDSFeesCannotReleaseStake(serviceProviderDetails.tokensUsed, claim.tokens);
                }
                serviceProviderDetails.tokensUsed -= claim.tokens;

                // Update list and refresh pointer
                serviceProviderDetails.stakeClaimHead = claim.nextClaim;
                delete claims[head];
                head = serviceProviderDetails.stakeClaimHead;
                if (!releaseAll) n--;

                emit StakeReleased(
                    serviceProvider,
                    serviceProviderDetails.stakeClaimHead,
                    claim.tokens,
                    claim.releaseAt
                );
            } else {
                break;
            }
        }
    }

    function _getStakeClaim(bytes32 claimId) private view returns (StakeClaim memory) {
        StakeClaim memory claim = claims[claimId];
        if (claim.createdAt == 0) {
            revert GDSFeesClaimNotFound(claimId);
        }
        return claim;
    }

    function _buildStakeClaimId(address serviceProvider, uint256 nonce) private view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), serviceProvider, nonce));
    }
}
