// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/// @title HexStrings
/// Based on https://github.com/OpenZeppelin/openzeppelin-contracts/blob/8dd744fc1843d285c38e54e9d439dea7f6b93495/contracts/utils/Strings.sol
library HexStrings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /// @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
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

    /// @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
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
