// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "./ITAPVerifier.sol";

interface ISubgraphService {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
        // Query fees state
        uint256 tokensUsed; // tokens being used as slashable stake
        bytes32 stakeClaimHead;
        bytes32 stakeClaimTail;
        uint256 stakeClaimNonce;
    }

    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens;
        uint256 createdAt;
        uint256 closedAt;
        uint256 accRewardsPerAllocatedToken;
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

    // register as a provider in the data service
    function register(address serviceProvider, string calldata url, string calldata geohash) external;

    function slash(address serviceProvider, uint256 tokens, uint256 reward) external;

    function redeem(ITAPVerifier.SignedRAV calldata rav) external returns (uint256 queryFees);

    function release(address serviceProvider, uint256 count) external;
}
