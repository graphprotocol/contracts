// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

/**
 * @title Roles
 * @notice A library that defines standard roles used across the protocol
 * 
 * @dev This library provides a centralized place to define role constants,
 * ensuring consistency across contracts. Using these constants instead of
 * redefining them in each contract reduces the risk of inconsistencies.
 */
library Roles {
    /// @notice Role for governance actions
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR_ROLE");

    /// @notice Role for pause actions
    bytes32 public constant PAUSE = keccak256("PAUSE_ROLE");

    /// @notice Role for operator actions
    bytes32 public constant OPERATOR = keccak256("OPERATOR_ROLE");

    /// @notice Role for oracle actions
    bytes32 public constant ORACLE = keccak256("ORACLE_ROLE");
}
