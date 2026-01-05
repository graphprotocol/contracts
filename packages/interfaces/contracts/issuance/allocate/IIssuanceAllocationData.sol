// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;
pragma abicoder v2;

import { AllocationTarget } from "./IIssuanceAllocatorTypes.sol";

/**
 * @title IIssuanceAllocationData
 * @author Edge & Node
 * @notice Interface for querying issuance allocation target data
 * @dev This interface provides access to internal allocation target information,
 * primarily useful for operators and off-chain monitoring systems.
 */
interface IIssuanceAllocationData {
    /**
     * @notice Get target data for a specific target
     * @param target Address of the target
     * @return AllocationTarget struct containing target information including lastChangeNotifiedBlock
     */
    function getTargetData(address target) external view returns (AllocationTarget memory);
}
