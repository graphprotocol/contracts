// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "@graphprotocol/horizon/contracts/data-service/extensions/IDataServiceFees.sol";

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

interface ISubgraphService is IDataServiceFees {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
    }

    struct PaymentCuts {
        uint128 percentageServiceCut;
        uint128 percentageCurationCut;
    }

    function resizeAllocation(address indexer, address allocationId, uint256 tokens) external;

    function migrateLegacyAllocation(address indexer, address allocationId, bytes32 subgraphDeploymentID) external;

    function setPauseGuardian(address pauseGuardian, bool allowed) external;

    function getAllocation(address allocationId) external view returns (Allocation.State memory);

    function getLegacyAllocation(address allocationId) external view returns (LegacyAllocation.State memory);

    function encodeAllocationProof(address indexer, address allocationId) external view returns (bytes32);
}
