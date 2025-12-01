// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title MockGraphToken
 * @notice Mock GraphToken for testing with minter role
 */
contract MockGraphToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => mapping(bytes32 => bool)) private _roles;
    mapping(address => bool) public minter;

    function grantRole(bytes32 role, address account) external {
        _roles[account][role] = true;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[account][role];
    }

    function setMinter(address account, bool value) external {
        minter[account] = value;
        if (value) {
            _roles[account][MINTER_ROLE] = true;
        } else {
            _roles[account][MINTER_ROLE] = false;
        }
    }

    function isMinter(address account) external view returns (bool) {
        return minter[account];
    }
}
