// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title ILegacyRewardsManager
 * @author Edge & Node
 * @notice Interface for the legacy rewards manager contract
 */
interface ILegacyRewardsManager {
    /**
     * @notice Get the accumulated rewards for a given allocation
     * @param allocationID The allocation identifier
     * @return The amount of accumulated rewards
     */
    function getRewards(address allocationID) external view returns (uint256);
}
