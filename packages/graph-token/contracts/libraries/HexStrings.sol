// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-increment-by-one

/**
 * @title HexStrings
 * @author Edge & Node
 * @notice Library for converting values to hexadecimal string representations
 * @dev Based on https://github.com/OpenZeppelin/openzeppelin-contracts/blob/8dd744fc1843d285c38e54e9d439dea7f6b93495/contracts/utils/Strings.sol
 */
library HexStrings {
    /// @dev Hexadecimal symbols used for string conversion
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /// @notice Converts a `uint256` to its ASCII `string` hexadecimal representation.
    /// @param value The uint256 value to convert
    /// @return The hexadecimal string representation
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /// @notice Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
    /// @param value The uint256 value to convert
    /// @param length The fixed length of the output string
    /// @return The hexadecimal string representation with fixed length
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}
