// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @dev Storage variables for the L1Reservoir
 */
contract L1ReservoirV1Storage {
    // Fraction of total rewards to be sent by L2, expressed in fixed point at 1e18
    uint256 public l2RewardsFraction;
    // New fraction of total rewards to be sent by L2, to be applied on the next drip
    uint256 public nextL2RewardsFraction;
    // Address for the L2Reservoir to which we send rewards
    address public l2ReservoirAddress;
    // Block until the minted supplies should last before another drip is needed
    uint256 public rewardsMintedUntilBlock;
    // Snapshot of initial token supply plus accumulated global rewards
    uint256 public tokenSupplyCache;
    // New issuance rate to be applied on the next drip
    uint256 public nextIssuanceRate;
    // Interval for rewards drip, in blocks
    uint256 public dripInterval;
    // Auto-incrementing nonce that will be used when sending rewards to L2, to ensure ordering
    uint256 public nextDripNonce;
}
