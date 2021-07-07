// SPDX-License-Identifier: MIT

import "../staking/libs/MathUtils.sol";

contract MathUtilsMock {
    function totalRatio(uint256 a, uint256 b) public pure returns (uint32) {
        return MathUtils.totalRatio(a, b);
    }

    function percentOf(uint32 percentage, uint256 value) public pure returns (uint256) {
        return MathUtils.percentOf(percentage, value);
    }
}
