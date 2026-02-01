// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IPausableControl } from "@graphprotocol/interfaces/contracts/issuance/common/IPausableControl.sol";

/**
 * @title BaseUpgradeable
 * @author Edge & Node
 * @notice A base contract that provides role-based access control and pausability.
 *
 * @dev This contract combines OpenZeppelin's AccessControl and Pausable
 * to provide a standardized way to manage access control and pausing functionality.
 * It uses ERC-7201 namespaced storage pattern for better storage isolation.
 * This contract is abstract and meant to be inherited by other contracts.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
abstract contract BaseUpgradeable is Initializable, AccessControlUpgradeable, PausableUpgradeable, IPausableControl {
    // -- Constants --

    /// @notice One million - used as the denominator for values provided as Parts Per Million (PPM)
    /// @dev This constant represents 1,000,000 and serves as the denominator when working with
    /// PPM values. For example, 50% would be represented as 500,000 PPM, calculated as
    /// (500,000 / MILLION) = 0.5 = 50%
    uint256 public constant MILLION = 1_000_000;

    // -- Role Constants --

    /**
     * @notice Role identifier for governor accounts
     * @dev Governors have the highest level of access and can:
     * - Grant and revoke roles within the established hierarchy
     * - Perform administrative functions and system configuration
     * - Set critical parameters and upgrade contracts
     * Admin of: GOVERNOR_ROLE, PAUSE_ROLE, OPERATOR_ROLE
     */
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /**
     * @notice Role identifier for pause accounts
     * @dev Pause role holders can:
     * - Pause and unpause contract operations for emergency situations
     * Typically granted to automated monitoring systems or emergency responders.
     * Pausing is intended for quick response to potential threats, and giving time for investigation and resolution (potentially with governance intervention).
     * Admin: GOVERNOR_ROLE
     */
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /**
     * @notice Role identifier for operator accounts
     * @dev Operators can:
     * - Perform operational tasks as defined by inheriting contracts
     * - Manage roles that are designated as operator-administered
     * Admin: GOVERNOR_ROLE
     */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -- Immutable Variables --

    /// @notice The Graph Token contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGraphToken internal immutable GRAPH_TOKEN;

    // -- Custom Errors --

    /// @notice Thrown when attempting to set the Graph Token to the zero address
    error GraphTokenCannotBeZeroAddress();

    /// @notice Thrown when attempting to set the governor to the zero address
    error GovernorCannotBeZeroAddress();

    // -- Constructor --

    /**
     * @notice Constructor for the BaseUpgradeable contract
     * @dev This contract is upgradeable, but we use the constructor to set immutable variables
     * and disable initializers to prevent the implementation contract from being initialized.
     * @param graphToken Address of the Graph Token contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken) {
        require(graphToken != address(0), GraphTokenCannotBeZeroAddress());
        GRAPH_TOKEN = IGraphToken(graphToken);
        _disableInitializers();
    }

    // -- Initialization --

    // solhint-disable-next-line func-name-mixedcase
    // forge-lint: disable-next-item(mixed-case-function)
    /**
     * @notice Internal function to initialize the BaseUpgradeable contract
     * @dev This function is used by child contracts to initialize the BaseUpgradeable contract
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    function __BaseUpgradeable_init(address governor) internal {
        __AccessControl_init();
        __Pausable_init();

        __BaseUpgradeable_init_unchained(governor);
    }

    /**
     * @notice Internal unchained initialization function for BaseUpgradeable
     * @dev This function sets up the governor role and role admin hierarchy
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __BaseUpgradeable_init_unchained(address governor) internal {
        // solhint-disable-previous-line func-name-mixedcase

        require(governor != address(0), GovernorCannotBeZeroAddress());

        // Set up role admin hierarchy:
        // GOVERNOR is admin of GOVERNOR, PAUSE, and OPERATOR roles
        _setRoleAdmin(GOVERNOR_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(PAUSE_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, GOVERNOR_ROLE);

        // Grant initial governor role
        _grantRole(GOVERNOR_ROLE, governor);
    }

    // -- External Functions --

    /**
     * @inheritdoc IPausableControl
     */
    function pause() external override onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /**
     * @inheritdoc IPausableControl
     */
    function unpause() external override onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /**
     * @inheritdoc IPausableControl
     */
    function paused() public view virtual override(PausableUpgradeable, IPausableControl) returns (bool) {
        return super.paused();
    }

    /**
     * @notice Check if this contract supports a given interface
     * @dev Adds support for IPausableControl interface
     * @param interfaceId The interface identifier to check
     * @return True if the contract supports the interface, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IPausableControl).interfaceId || super.supportsInterface(interfaceId);
    }
}
