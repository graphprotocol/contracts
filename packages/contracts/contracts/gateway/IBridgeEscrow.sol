// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

/**
 * @title IBridgeEscrow
 */
interface IBridgeEscrow {
    /**
     * @notice Initialize the BridgeEscrow contract.
     * @param _controller Address of the Controller that manages this contract
     */
    function initialize(address _controller) external;

    /**
     * @notice Approve a spender (i.e. a bridge that manages the GRT funds held by the escrow)
     * @param _spender Address of the spender that will be approved
     */
    function approveAll(address _spender) external;

    /**
     * @notice Revoke a spender (i.e. a bridge that will no longer manage the GRT funds held by the escrow)
     * @param _spender Address of the spender that will be revoked
     */
    function revokeAll(address _spender) external;
}