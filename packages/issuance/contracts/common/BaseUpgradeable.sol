// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { Roles } from "./Roles.sol";

/**
 * @title BaseUpgradeable
 * @notice A base contract that provides role-based access control, pausability, and reentrancy protection.
 *
 * @dev This contract combines OpenZeppelin's AccessControl, Pausable, and ReentrancyGuard
 * to provide a standardized way to manage access control and pausing functionality.
 * It uses ERC-7201 namespaced storage pattern for better storage isolation.
 */
contract BaseUpgradeable is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{

    // -- Immutable Variables --

    /// @notice The Graph Token contract
    IGraphToken internal immutable GRAPH_TOKEN;

    // -- Constants --

    /// @notice Parts per million (100%)
    uint256 public constant PPM = 1_000_000;

    // -- Custom Errors --

    /// @notice Thrown when attempting to set the Graph Token to the zero address
    error GraphTokenCannotBeZeroAddress();
    error GovernorCannotBeZeroAddress();

    /**
     * @notice Constructor for the BaseUpgradeable contract
     * @dev This contract is upgradeable, but we use the constructor to set immutable variables
     * and disable initializers to prevent the implementation contract from being initialized.
     * @param _graphToken Address of the Graph Token contract
     */
    constructor(address _graphToken) {
        if (_graphToken == address(0)) revert GraphTokenCannotBeZeroAddress();
        GRAPH_TOKEN = IGraphToken(_graphToken);
        _disableInitializers();
    }

    /**
     * @notice Initialize the BaseUpgradeable contract
     * @param _governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address _governor) external virtual initializer {
        if (_governor == address(0)) revert GovernorCannotBeZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        // Note: We're not setting any role admins or granting DEFAULT_ADMIN_ROLE
        // All role management is done through the explicit functions that use
        // the internal _grantRole and _revokeRole functions directly
        _grantRole(Roles.GOVERNOR, _governor);
    }

    /**
     * @notice Pause the contract
     * @dev Only callable by accounts with the PAUSE_ROLE
     */
    function pause() external onlyRole(Roles.PAUSE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by accounts with the PAUSE_ROLE
     */
    function unpause() external onlyRole(Roles.PAUSE) {
        _unpause();
    }

    /**
     * @notice Grant the pause role to an account
     * @dev Only callable by accounts with the GOVERNOR_ROLE
     * @param _account Address to grant the pause role to
     * @return True if the role was granted, false if the account already had the role
     */
    function grantPauseRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _grantRole(Roles.PAUSE, _account);
    }

    /**
     * @notice Revoke the pause role from an account
     * @dev Only callable by accounts with the GOVERNOR_ROLE
     * @param _account Address to revoke the pause role from
     * @return True if the role was revoked, false if the account didn't have the role
     */
    function revokePauseRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _revokeRole(Roles.PAUSE, _account);
    }

    /**
     * @notice Grant the governor role to an account
     * @dev Only callable by accounts with the GOVERNOR_ROLE
     * @param _account Address to grant the governor role to
     * @return True if the role was granted, false if the account already had the role
     */
    function grantGovernorRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _grantRole(Roles.GOVERNOR, _account);
    }

    /**
     * @notice Revoke the governor role from an account
     * @dev Only callable by accounts with the GOVERNOR_ROLE
     * @param _account Address to revoke the governor role from
     * @return True if the role was revoked, false if the account didn't have the role
     */
    function revokeGovernorRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _revokeRole(Roles.GOVERNOR, _account);
    }

    /**
     * @notice Grant the operator role to an account
     * @param _account Address to grant the operator role to
     * @return True if the role was granted, false if the account already had the role
     */
    function grantOperatorRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _grantRole(Roles.OPERATOR, _account);
    }

    /**
     * @notice Revoke the operator role from an account
     * @param _account Address to revoke the operator role from
     * @return True if the role was revoked, false if the account didn't have the role
     */
    function revokeOperatorRole(address _account) external onlyRole(Roles.GOVERNOR) returns (bool) {
        return _revokeRole(Roles.OPERATOR, _account);
    }

    /**
     * @notice Get the current balance of GRT tokens in this contract
     * @return Current balance of GRT tokens
     */
    function getBalance() external view returns (uint256) {
        return GRAPH_TOKEN.balanceOf(address(this));
    }
}
