// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

/**
 * @title ArbSys Mock Contract
 * @dev This is a mock implementation of the ArbSys precompiled contract used in Arbitrum
 * It's used for testing the L2GraphTokenGateway contract
 */
contract ArbSysMock {
    event L2ToL1Tx(address indexed from, address indexed to, uint256 indexed id, bytes data);

    /**
     * @notice Send a transaction to L1
     * @param destination The address on L1 to send the transaction to
     * @param calldataForL1 The calldata for the transaction
     * @return A unique identifier for this L2-to-L1 transaction
     */
    function sendTxToL1(address destination, bytes calldata calldataForL1) external returns (uint256) {
        uint256 id = 1; // Always return 1 for testing
        emit L2ToL1Tx(msg.sender, destination, id, calldataForL1);
        return id;
    }
}
