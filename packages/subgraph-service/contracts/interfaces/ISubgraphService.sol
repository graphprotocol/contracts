// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "./ITAPVerifier.sol";

interface ISubgraphService {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
    }

    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens;
        uint256 createdAt;
        uint256 closedAt;
        uint256 accRewardsPerAllocatedToken;
    }

    // register as a provider in the data service
    function register(address serviceProvider, string calldata url, string calldata geohash) external;

    function slash(address serviceProvider, uint256 tokens, uint256 reward) external;

    function redeem(ITAPVerifier.SignedRAV calldata rav) external returns (uint256 queryFees);

    function allocate(
        address serviceProvider,
        bytes32 subgraphDeploymentId,
        uint256 tokens,
        address allocationId,
        bytes32 metadata,
        bytes calldata proof
    ) external;

    function getAllocation(address allocationID) external view returns (Allocation memory);

    function encodeProof(address indexer, address allocationId) external view returns (bytes32);
}
