// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IDataServiceFees } from "../data-service/extensions/IDataServiceFees.sol";
import { Allocation } from "../libraries/Allocation.sol";

interface ISubgraphService is IDataServiceFees {
    struct Indexer {
        uint256 registeredAt;
        string url;
        string geoHash;
    }

    function getAllocation(address allocationID) external view returns (Allocation.State memory);
}
