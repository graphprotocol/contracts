// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

library UintRange {
    using UintRange for uint256;

    function isInRange(uint256 self, uint256 min, uint256 max) internal pure returns (bool) {
        return self >= min && self <= max;
    }
}
