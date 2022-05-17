// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../reservoir/Reservoir.sol";

// Mock contract used for testing rewards
contract ReservoirMock is Reservoir {
    function getNewRewards(uint256) public view override returns (uint256 r) {}

    /**
     * @dev Raises x to the power of n with scaling factor of base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param x Base of the exponentiation
     * @param n Exponent
     * @param base Scaling factor
     * @return z Exponential of n with base x
     */
    function pow(
        uint256 x,
        uint256 n,
        uint256 base
    ) public pure returns (uint256 z) {
        z = _pow(x, n, base);
    }
}
