// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

/**
 * @title UintRange library
 * @notice A library for handling range checks on uint256 values.
 */
library UintRange {
    using UintRange for uint256;

    /**
     * @notice Checks if a value is in the range [`min`, `max`].
     * @param value The value to check.
     * @param min The minimum value of the range.
     * @param max The maximum value of the range.
     */
    function isInRange(uint256 value, uint256 min, uint256 max) internal pure returns (bool) {
        return value >= min && value <= max;
    }
}
