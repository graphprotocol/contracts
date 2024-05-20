// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

library PPMMath {
    /// @notice Maximum value in parts per million (PPM).
    uint256 internal constant MAX_PPM = 1_000_000;

    error PPMMathInvalidPPM(uint256 ppm);
    error PPMMathInvalidMulPPM(uint256 a, uint256 b);

    // one of a or b must be in PPM
    function mulPPM(uint256 a, uint256 b) internal pure returns (uint256) {
        if (!isValidPPM(a) && !isValidPPM(b)) {
            revert PPMMathInvalidMulPPM(a, b);
        }
        return (a * b) / MAX_PPM;
    }

    // Calculate the tokens after curation fees first, and subtact that,
    // to prevent curation fees from rounding down to zero
    // a must be in ppm
    function mulPPMRoundUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (!isValidPPM(a)) {
            revert PPMMathInvalidPPM(a);
        }
        return b - mulPPM(MAX_PPM - a, b);
    }

    function isValidPPM(uint256 ppm) internal pure returns (bool) {
        return ppm >= 0 && ppm <= MAX_PPM;
    }
}
