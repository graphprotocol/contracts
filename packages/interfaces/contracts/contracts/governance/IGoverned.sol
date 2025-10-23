// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IGoverned
 * @author Edge & Node
 * @notice Interface for governed contracts
 */
interface IGoverned {
    // -- State getters --

    /**
     * @notice Get the current governor address
     * @return The address of the current governor
     */
    function governor() external view returns (address);

    /**
     * @notice Get the pending governor address
     * @return The address of the pending governor
     */
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

    /**
     * @notice Emitted when a new pending governor is set
     * @param from The address of the current governor
     * @param to The address of the new pending governor
     */
    event NewPendingOwnership(address indexed from, address indexed to);

    /**
     * @notice Emitted when governance is transferred to a new governor
     * @param from The address of the previous governor
     * @param to The address of the new governor
     */
    event NewOwnership(address indexed from, address indexed to);
}
