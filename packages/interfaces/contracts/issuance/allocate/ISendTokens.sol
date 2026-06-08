// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title ISendTokens
 * @author Edge & Node
 * @notice Interface for contracts that can send tokens to arbitrary addresses
 * @dev This interface provides a simple token transfer capability for contracts
 * that need to distribute or send tokens programmatically.
 */
interface ISendTokens {
    /**
     * @notice Send tokens to a specified address
     * @param to The address to send tokens to
     * @param amount The amount of tokens to send
     */
    function sendTokens(address to, uint256 amount) external;
}
