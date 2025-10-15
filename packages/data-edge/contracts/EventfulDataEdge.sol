// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.12;

/// @title Data Edge contract is only used to store on-chain data, it does not
///        perform execution. On-chain client services can read the data
///        and decode the payload for different purposes.
///        NOTE: This version emits an event with the calldata.
/// @author Edge & Node
/// @notice Contract for storing on-chain data with event logging
contract EventfulDataEdge {
    /// @notice Emitted when data is received
    /// @param data The calldata received by the contract
    event Log(bytes data);

    /// @notice Accepts any payload and emits it as an event
    /// @dev Fallback function, accepts any payload
    fallback() external payable {
        emit Log(msg.data);
    }
}
