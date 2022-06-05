// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @dev Storage variables for the L2Reservoir
 */
contract L2ReservoirV1Storage {
    // Expected nonce value for the next drip hook
    uint256 public nextDripNonce;
}

contract L2ReservoirV2Storage is L2ReservoirV1Storage {
    // Fraction of the keeper reward to send to the retryable tx redeemer in L2 (fixed point 1e18)
    uint256 public l2KeeperRewardFraction;
}
