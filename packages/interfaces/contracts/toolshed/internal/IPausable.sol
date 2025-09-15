// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title IPausable
/// @notice Interface for Pausable contract
interface IPausable {
    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /// @notice Returns true if the contract is paused, and false otherwise
    function paused() external view returns (bool);
}
