// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable use-natspec

library MathUtils {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
