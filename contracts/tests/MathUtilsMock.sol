// SPDX-License-Identifier: MIT

import "../staking/libs/MathUtils.sol";

contract MathUtilsMock {
    function totalRatio(uint256 a, uint256 b) public pure returns (uint32) {
        return MathUtils.totalRatio(a, b);
    }
}
