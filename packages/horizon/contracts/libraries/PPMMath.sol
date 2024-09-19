// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title PPMMath library
 * @notice A library for handling calculations with parts per million (PPM) amounts.
 */
library PPMMath {
    /// @notice Maximum value (100%) in parts per million (PPM).
    uint256 internal constant MAX_PPM = 1_000_000;

    /**
     * @notice Thrown when a value is expected to be in PPM but is not.
     * @param value The value that is not in PPM.
     */
    error PPMMathInvalidPPM(uint256 value);

    /**
     * @notice Thrown when no value in a multiplication is in PPM.
     * @param a The first value in the multiplication.
     * @param b The second value in the multiplication.
     */
    error PPMMathInvalidMulPPM(uint256 a, uint256 b);

    /**
     * @notice Multiplies two values, one of which must be in PPM.
     * @param a The first value.
     * @param b The second value.
     * @return The result of the multiplication.
     */
    function mulPPM(uint256 a, uint256 b) internal pure returns (uint256) {
        require(isValidPPM(a) || isValidPPM(b), PPMMathInvalidMulPPM(a, b));
        return (a * b) / MAX_PPM;
    }

    /**
     * @notice Multiplies two values, the second one must be in PPM, and rounds up the result.
     * @dev requirements:
     * - The second value must be in PPM.
     * @param a The first value.
     * @param b The second value.
     */
    function mulPPMRoundUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(isValidPPM(b), PPMMathInvalidPPM(b));
        return a - mulPPM(a, MAX_PPM - b);
    }

    /**
     * @notice Checks if a value is in PPM.
     * @dev A valid PPM value is between 0 and MAX_PPM.
     * @param value The value to check.
     */
    function isValidPPM(uint256 value) internal pure returns (bool) {
        return value <= MAX_PPM;
    }
}
