// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockGraphToken
/// @author Edge & Node
/// @notice Mock contract for testing IssuanceStateVerifier
contract MockGraphToken {
    mapping(address => bool) private _minters;

    /// @notice Sets the minter status for an account
    /// @param account The account to set minter status for
    /// @param minterStatus True to grant minter role, false to revoke
    function setMinter(address account, bool minterStatus) external {
        _minters[account] = minterStatus;
    }

    /// @notice Checks if an account has minter role
    /// @param account The account to check
    /// @return True if the account is a minter, false otherwise
    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }
}
