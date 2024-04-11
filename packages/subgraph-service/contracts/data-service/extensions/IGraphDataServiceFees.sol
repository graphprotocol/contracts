// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

interface IGraphDataServiceFees {
    struct FeesServiceProvider {
        uint256 tokensUsed;
        bytes32 stakeClaimHead;
        bytes32 stakeClaimTail;
        uint256 stakeClaimNonce;
    }

    /// A locked stake claim to be released to a service provider
    struct StakeClaim {
        address indexer;
        // tokens to be released with this claim
        uint256 tokens;
        uint256 createdAt;
        // timestamp when the claim can be released
        uint256 releaseAt;
        // next claim in the linked list
        bytes32 nextClaim;
    }
}
