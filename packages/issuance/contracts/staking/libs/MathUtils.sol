// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-strict-inequalities

/**
 * @title MathUtils Library
 * @author Edge & Node
 * @notice A collection of functions to perform math operations
 */
library MathUtils {
    /**
     * @notice Returns the difference between two numbers or zero if negative.
     * @param x First number
     * @param y Second number
     * @return The difference x - y, or 0 if y > x
     */
    function diffOrZero(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y) ? x - y : 0;
    }
}
