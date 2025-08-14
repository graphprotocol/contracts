// SPDX-License-Identifier: GPL-2.0-or-later

/**
 * @title Interface for contracts that can receive callhooks through the Arbitrum GRT bridge
 * @author Edge & Node
 * @notice Any contract that can receive a callhook on L2, sent through the bridge from L1, must
 * be allowlisted by the governor, but also implement this interface that contains
 * the function that will actually be called by the L2GraphTokenGateway.
 */
pragma solidity ^0.7.6;

/**
 * @title Callhook Receiver Interface
 * @author Edge & Node
 * @notice Interface for contracts that can receive tokens with callhook from the bridge
 */
interface ICallhookReceiver {
    /**
     * @notice Receive tokens with a callhook from the bridge
     * @param _from Token sender in L1
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data
     */
    function onTokenTransfer(address _from, uint256 _amount, bytes calldata _data) external;
}
