// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "../../reservoir/IReservoir.sol";

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
     * Note that the transaction might revert if it's received out-of-order,
     * because it checks an incrementing nonce. If that is the case, the retryable ticket can be redeemed
     * again once the ticket for previous drip has been redeemed.
     * A keeper reward will be sent to the keeper that dripped on L1, and part of it
     * to whoever redeemed the current retryable ticket (tx.origin)
     * @param _issuanceBase Base value for token issuance (approximation for token supply times L2 rewards fraction)
     * @param _issuanceRate Rewards issuance rate, using fixed point at 1e18, and including a +1
     * @param _nonce Incrementing nonce to ensure messages are received in order
     * @param _keeperReward Keeper reward to distribute between keeper that called drip and keeper that redeemed  the retryable tx
     * @param _l1Keeper Address of the keeper that called drip in L1
     */
    function receiveDrip(
        uint256 _issuanceBase,
        uint256 _issuanceRate,
        uint256 _nonce,
        uint256 _keeperReward,
        address _l1Keeper
    ) external;
}
