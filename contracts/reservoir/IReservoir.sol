// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @title Interface for the Rewards Reservoir
 * @dev This is the shared interface between L1 and L2, for the contracts
 * that hold rewards on each layers and provide functions to compute
 * accumulated and new total rewards.
 */
interface IReservoir {
    // Emitted when the issuance rate is updated
    event IssuanceRateUpdated(uint256 newValue);

    /**
     * @dev Approve the RewardsManager to manage the reservoir's token funds
     */
    function approveRewardsManager() external;

    /**
     * @dev Get accumulated total rewards on this layer at a particular block
     * @param _blocknum Block number at which to calculate rewards
     * @return Accumulated total rewards on this layer
     */
    function getAccumulatedRewards(uint256 _blocknum) external view returns (uint256);

    /**
     * @dev Get new total rewards on this layer at a particular block, since the last drip event
     * @param _blocknum Block number at which to calculate rewards
     * @return New total rewards on this layer since the last drip
     */
    function getNewRewards(uint256 _blocknum) external view returns (uint256);
}
