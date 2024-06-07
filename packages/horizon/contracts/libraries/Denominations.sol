// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

/**
 * @title Denominations library
 * @dev Provides a list of ground denominations for those tokens that cannot be represented by an ERC20.
 * For now, the only needed is the native token that could be ETH, MATIC, or other depending on the layer being operated.
 */
library Denominations {
    /// @notice The address of the native token, i.e ETH
    /// @dev This convention is taken from https://eips.ethereum.org/EIPS/eip-7528
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Checks if a token is the native token
     * @param token The token address to check
     * @return True if the token is the native token, false otherwise
     */
    function isNativeToken(address token) internal pure returns (bool) {
        return token == NATIVE_TOKEN;
    }
}
