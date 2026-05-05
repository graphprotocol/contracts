// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IEmergencyRoleControl
 * @author Edge & Node
 * @notice Interface for emergency role revocation by pause-role holders.
 * @dev Provides a surgical alternative to pausing: disable a specific actor
 * (operator, collector, data service) without halting the entire contract.
 * Only the governor (role admin) can re-grant revoked roles.
 */
interface IEmergencyRoleControl {
    /**
     * @notice Emergency role revocation by pause-role holder
     * @dev Allows pause-role holders to revoke any non-governor role as a fast-response
     * emergency measure. Governor role is excluded to prevent a pause guardian from
     * locking out governance.
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function emergencyRevokeRole(bytes32 role, address account) external;
}
