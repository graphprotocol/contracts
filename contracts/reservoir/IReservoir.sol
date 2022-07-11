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
    event IssuanceRateUpdated(uint256 _newValue);

    /**
     * @dev Approve the RewardsManager to manage the reservoir's token funds
     */
    function approveRewardsManager() external;

    /**
     * @dev Get accumulated total rewards on this layer at a particular block
     * @param blocknum Block number at which to calculate rewards
     * @return totalRewards Accumulated total rewards on this layer
     */
    function getAccumulatedRewards(uint256 blocknum) external view returns (uint256 totalRewards);

    /**
     * @dev Get new total rewards on this layer at a particular block, since the last drip event
     * @param blocknum Block number at which to calculate rewards
     * @return deltaRewards New total rewards on this layer since the last drip
     */
    function getNewRewards(uint256 blocknum) external view returns (uint256 deltaRewards);
}

/**
 * @title Interface for the L2 Rewards Reservoir
 * @dev This exposes a specific function for the L2Reservoir that is called
 * as a callhook from L1 to L2, so that state can be updated when dripped rewards
 * are bridged between layers.
 */
interface IL2Reservoir is IReservoir {
    /**
     * @dev Receive dripped tokens from L1.
     * This function can only be called by the gateway, as it is
     * meant to be a callhook when receiving tokens from L1. It
     * updates the issuanceBase and issuanceRate,
     * and snapshots the accumulated rewards. If issuanceRate changes,
     * it also triggers a snapshot of rewards per signal on the RewardsManager.
     * @param _issuanceBase Base value for token issuance (approximation for token supply times L2 rewards fraction)
     * @param _issuanceRate Rewards issuance rate, using fixed point at 1e18, and including a +1
     * @param _nonce Incrementing nonce to ensure messages are received in order
     */
    function receiveDrip(
        uint256 _issuanceBase,
        uint256 _issuanceRate,
        uint256 _nonce
    ) external;
}
