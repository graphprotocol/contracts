// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title UintRange library
 * @notice A library for handling range checks on uint256 values.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
library UintRange {
    /**
     * @notice Checks if a value is in the range [`min`, `max`].
     * @param value The value to check.
     * @param min The minimum value of the range.
     * @param max The maximum value of the range.
     * @return true if the value is in the range, false otherwise.
     */
    function isInRange(uint256 value, uint256 min, uint256 max) internal pure returns (bool) {
        return value >= min && value <= max;
    }
}
