// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IssuanceAllocator } from "../../allocate/IssuanceAllocator.sol";

/**
 * @title IssuanceAllocatorTestHarness
 * @author Edge & Node
 * @notice Test harness to expose internal functions for white-box testing
 * @dev This contract allows direct testing of internal distribution functions to achieve 100% coverage
 */
contract IssuanceAllocatorTestHarness is IssuanceAllocator {
    /**
     * @notice Constructor for the test harness
     * @param _graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address _graphToken) IssuanceAllocator(_graphToken) {}

    /**
     * @notice Exposes _distributePendingProportionally for testing
     * @dev Allows testing of defensive checks and edge cases
     * @param available Total available allocator-minting budget for the period
     * @param allocatedRate Total rate allocated to non-default targets
     * @param toBlockNumber Block number distributing to
     */
    function exposed_distributePendingProportionally(
        uint256 available,
        uint256 allocatedRate,
        uint256 toBlockNumber
    ) external {
        _distributePendingProportionally(available, allocatedRate, toBlockNumber);
    }

    /**
     * @notice Exposes _distributePendingWithFullRate for testing
     * @dev Allows testing of edge cases in full rate distribution
     * @param blocks Number of blocks in the distribution period
     * @param available Total available allocator-minting budget for the period
     * @param allocatedTotal Total amount allocated to non-default targets at full rate
     * @param toBlockNumber Block number distributing to
     */
    function exposed_distributePendingWithFullRate(
        uint256 blocks,
        uint256 available,
        uint256 allocatedTotal,
        uint256 toBlockNumber
    ) external {
        _distributePendingWithFullRate(blocks, available, allocatedTotal, toBlockNumber);
    }
}
