// SPDX-License-Identifier: MIT
// solhint-disable use-natspec

pragma solidity ^0.8.22;

/// @title IOwnable
/// @notice Interface for Ownable contracts
interface IOwnable {
    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /// @notice Returns the address of the current owner
    function owner() external view returns (address);

    /// @notice Leaves the contract without an owner
    function renounceOwnership() external;

    /// @notice Transfers ownership of the contract to a new account
    /// @param newOwner The address of the new owner
    function transferOwnership(address newOwner) external;
}
