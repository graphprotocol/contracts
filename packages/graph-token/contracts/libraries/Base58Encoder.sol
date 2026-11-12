// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one

/**
 * @title Base58Encoder
 * @author Original author - Martin Lundfall (martin.lundfall@gmail.com)
 * @notice Library for encoding bytes to Base58 format, used for IPFS hashes
 * @dev Based on https://github.com/MrChico/verifyIPFS
 */
library Base58Encoder {
    /// @dev SHA-256 multihash prefix for IPFS hashes
    // solhint-disable-next-line const-name-snakecase
    bytes internal constant sha256MultiHash = hex"1220";
    /// @dev Base58 alphabet used for encoding
    bytes internal constant ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    /// @notice Converts hex string to base 58
    /// @param source The bytes to encode
    /// @return The base58 encoded bytes
    function encode(bytes memory source) internal pure returns (bytes memory) {
        if (source.length == 0) return new bytes(0);
        uint8[] memory digits = new uint8[](64);
        digits[0] = 0;
        uint8 digitlength = 1;
        for (uint256 i = 0; i < source.length; ++i) {
            uint256 carry = uint8(source[i]);
            for (uint256 j = 0; j < digitlength; ++j) {
                carry += uint256(digits[j]) * 256;
                digits[j] = uint8(carry % 58);
                carry = carry / 58;
            }

            while (carry > 0) {
                digits[digitlength] = uint8(carry % 58);
                digitlength++;
                carry = carry / 58;
            }
        }
        return toAlphabet(reverse(truncate(digits, digitlength)));
    }

    /**
     * @notice Truncate an array to a specific length
     * @param array The array to truncate
     * @param length The desired length
     * @return The truncated array
     */
    function truncate(uint8[] memory array, uint8 length) internal pure returns (uint8[] memory) {
        uint8[] memory output = new uint8[](length);
        for (uint256 i = 0; i < length; i++) {
            output[i] = array[i];
        }
        return output;
    }

    /**
     * @notice Reverse an array
     * @param input The array to reverse
     * @return The reversed array
     */
    function reverse(uint8[] memory input) internal pure returns (uint8[] memory) {
        uint8[] memory output = new uint8[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = input[input.length - 1 - i];
        }
        return output;
    }

    /**
     * @notice Convert indices to alphabet characters
     * @param indices The indices to convert
     * @return The alphabet characters as bytes
     */
    function toAlphabet(uint8[] memory indices) internal pure returns (bytes memory) {
        bytes memory output = new bytes(indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            output[i] = ALPHABET[indices[i]];
        }
        return output;
    }
}
