// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || ^0.8.27;

/**
 * @title IMulticall
 * @dev Interface for the Multicall contract.
 */
interface IMulticall {
    /**
     * @notice Receives and executes a batch of function calls on this contract.
     * @param data Calldata for each function call.
     * @return results Return data from each function call.
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
