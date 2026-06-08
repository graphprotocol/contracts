// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IPausableControl
 * @author Edge & Node
 * @notice Interface for contracts that support pause/unpause functionality
 * @dev This interface extends standard pausable functionality with explicit
 * pause and unpause functions. Contracts implementing this interface allow
 * authorized accounts to pause and unpause contract operations.
 * Events (Paused, Unpaused) are inherited from OpenZeppelin's PausableUpgradeable.
 */
interface IPausableControl {
    /**
     * @notice Pause the contract
     * @dev Pauses contract operations. Only functions using whenNotPaused
     * modifier will be affected.
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     * @dev Resumes contract operations. Only functions using whenPaused
     * modifier will be affected.
     */
    function unpause() external;

    /**
     * @notice Check if the contract is currently paused
     * @return True if the contract is paused, false otherwise
     */
    function paused() external view returns (bool);
}
