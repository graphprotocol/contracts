// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

contract MockCuration {
    function isCurated(bytes32) public pure returns (bool) {
        return true;
    }

    function collect(bytes32, uint256) external {}
}