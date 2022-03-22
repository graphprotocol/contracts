// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title MathUtils Library
 * @notice A collection of functions to perform math operations
 */
library MathUtils {
    using SafeMath for uint256;

    // 100% in parts per million
    uint32 public constant MAX_PPM = 1000000;

    /**
     * @dev Calculates the weighted average of two values pondering each of these
     * values based on configured weights. The contribution of each value N is
     * weightN/(weightA + weightB).
     * @param valueA The amount for value A
     * @param weightA The weight to use for value A
     * @param valueB The amount for value B
     * @param weightB The weight to use for value B
     */
    function weightedAverage(
        uint256 valueA,
        uint256 weightA,
        uint256 valueB,
        uint256 weightB
    ) internal pure returns (uint256) {
        return valueA.mul(weightA).add(valueB.mul(weightB)).div(weightA.add(weightB));
    }

    /**
     * @dev Returns the minimum of two numbers.
     */
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x <= y ? x : y;
    }

    /**
     * @dev Returns the difference between two numbers or zero if negative.
     */
    function diffOrZero(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y) ? x.sub(y) : 0;
    }

    /**
     * @dev Cast a number to uint32 and ensures that it is within percent expressed
     * in parts-per-million max bound.
     * @param value Value to cast and check is PPM
     * @return Number within a percentage bounds (PPM)
     */
    function toPercent(uint256 value) internal pure returns (uint32) {
        require(value <= MAX_PPM, "PercentCast: out of bounds");
        return uint32(value);
    }

    /**
     * @dev Returns the value after applying percentage with parts-per-million precision.
     * This function will not allow percentages over 100%
     * @param percentage Percentage (PPM)
     * @param value Value to calculate the percentage of
     * @return Percentage of a number
     */
    function percentOf(uint32 percentage, uint256 value) internal pure returns (uint256) {
        if (percentage == 0 || value == 0) return 0;
        return percentage >= MAX_PPM ? value : uint256(percentage).mul(value).div(MAX_PPM);
    }
}
