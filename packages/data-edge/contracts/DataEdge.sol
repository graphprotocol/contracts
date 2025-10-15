// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.12;

/// @title Data Edge contract is only used to store on-chain data, it does not
///        perform execution. On-chain client services can read the data
///        and decode the payload for different purposes.
/// @author Edge & Node
/// @notice Contract for storing on-chain data without execution
contract DataEdge {
    /// @notice Fallback function, accepts any payload
    fallback() external payable {
        // no-op
    }
}
