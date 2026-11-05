// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-strict-inequalities

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title MathUtils Library
 * @author Edge & Node
 * @notice A collection of functions to perform math operations
 */
library MathUtils {
    using SafeMath for uint256;

    /**
     * @notice Calculates the weighted average of two values pondering each of these
     * values based on configured weights. The contribution of each value N is
     * weightN/(weightA + weightB). The calculation rounds up to ensure the result
     * is always greater than the smallest of the two values.
     * @param valueA The amount for value A
     * @param weightA The weight to use for value A
     * @param valueB The amount for value B
     * @param weightB The weight to use for value B
     * @return The weighted average of the two values, rounded up
     */
    function weightedAverageRoundingUp(
        uint256 valueA,
        uint256 weightA,
        uint256 valueB,
        uint256 weightB
    ) internal pure returns (uint256) {
        return valueA.mul(weightA).add(valueB.mul(weightB)).add(weightA.add(weightB).sub(1)).div(weightA.add(weightB));
    }

    /**
     * @notice Returns the minimum of two numbers.
     * @param x First number
     * @param y Second number
     * @return The smaller of the two numbers
     */
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    /**
     * @notice Returns the difference between two numbers or zero if negative.
     * @param x First number
     * @param y Second number
     * @return The difference x - y, or 0 if y > x
     */
    function diffOrZero(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y) ? x.sub(y) : 0;
    }
}
