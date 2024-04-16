// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "../data-service/extensions/IDataServiceFees.sol";

interface ISubgraphService is IDataServiceFees {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
    }

    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
        uint256 createdAt;
        uint256 closedAt;
        uint256 accRewardsPerAllocatedToken;
    }

    function getAllocation(address allocationID) external view returns (Allocation memory);

    function encodeProof(address indexer, address allocationId) external view returns (bytes32);
}
