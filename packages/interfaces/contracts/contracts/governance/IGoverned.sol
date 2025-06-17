// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

/**
 * @title IGoverned
 * @dev Interface for the Governed contract.
 */
interface IGoverned {
    // -- State getters --

    function governor() external view returns (address);

    function pendingGovernor() external view returns (address);

    // -- External functions --

    /**
     * @notice Admin function to begin change of governor.
     * @param newGovernor Address of new `governor`
     */
    function transferOwnership(address newGovernor) external;

    /**
     * @notice Admin function for pending governor to accept role and update governor.
     */
    function acceptOwnership() external;

    // -- Events --

    event NewPendingOwnership(address indexed from, address indexed to);

    event NewOwnership(address indexed from, address indexed to);
}
