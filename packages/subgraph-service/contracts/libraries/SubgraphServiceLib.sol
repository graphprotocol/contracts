// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "../interfaces/ISubgraphService.sol";
import { AllocationManager } from "../utilities/AllocationManager.sol";
import { Allocation } from "./Allocation.sol";

library SubgraphServiceLib {
    using Allocation for mapping(address => Allocation.State);
    using Allocation for Allocation.State;

    function requireValidAllocation(
        mapping(address => Allocation.State) storage self,
        address allocationId,
        address indexer
    ) external view returns (Allocation.State memory) {
        Allocation.State memory allocation = self.get(allocationId);
        require(
            allocation.indexer == indexer,
            ISubgraphService.SubgraphServiceAllocationNotAuthorized(indexer, allocationId)
        );
        require(allocation.isOpen(), AllocationManager.AllocationManagerAllocationClosed(allocationId));

        return allocation;
    }
}
