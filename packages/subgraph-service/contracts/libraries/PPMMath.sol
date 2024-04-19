// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library PPMMath {
    /// @notice Maximum value in parts per million (PPM).
    uint256 private constant MAX_PPM = 1_000_000;

    function mulPPM(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / MAX_PPM;
    }
}
