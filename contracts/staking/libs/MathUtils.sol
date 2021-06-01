// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";

/**
 * @title MathUtils Library
 * @notice A collection of functions to perform math operations.
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
     * @dev Returns the ratio a/b using PPM scaling precision.
     * Both `a` and `b` must have the same scaling.
     */
    function ratio(uint256 a, uint256 b) internal pure returns (uint32) {
        return SafeCast.toUint32(a.mul(MAX_PPM).div(b));
    }

    /**
     * @dev Returns the percentage of value with parts-per-million precision.
     * @param percentage Percentage in parts-per-million (PPM)
     * @param value Value to calcuate the percentage of
     */
    function percentOf(uint32 percentage, uint256 value) internal pure returns (uint256) {
        return uint256(percentage).mul(value).div(MAX_PPM);
    }
}
