// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IGraphToken
 * @notice Minimal interface for GraphToken used in tests
 */
interface IGraphToken {
    function isMinter(address account) external view returns (bool);
}
