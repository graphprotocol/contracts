// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title IPausable
/// @notice Interface for Pausable contract
interface IPausable {
    /// @notice Returns true if the contract is paused, and false otherwise
    function paused() external view returns (bool);

    /**
     * @notice Pauses the contract
     */
    function pause() external;

    /**
     * @notice Unpauses the contract
     */
    function unpause() external;
}
