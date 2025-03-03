// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for the {DataServicePausable} contract.
 * @notice Extension for the {IDataService} contract, adds pausing functionality
 * to the data service. Pausing is controlled by privileged accounts called
 * pause guardians.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IDataServicePausable is IDataService {
    /**
     * @notice Emitted when a pause guardian is set.
     * @param account The address of the pause guardian
     * @param allowed The allowed status of the pause guardian
     */
    event PauseGuardianSet(address indexed account, bool allowed);

    /**
     * @notice Emitted when a the caller is not a pause guardian
     * @param account The address of the pause guardian
     */
    error DataServicePausableNotPauseGuardian(address account);

    /**
     * @notice Emitted when a pause guardian is set to the same allowed status
     * @param account The address of the pause guardian
     * @param allowed The allowed status of the pause guardian
     */
    error DataServicePausablePauseGuardianNoChange(address account, bool allowed);

    /**
     * @notice Pauses the data service.
     * @dev Note that only functions using the modifiers `whenNotPaused`
     * and `whenPaused` will be affected by the pause.
     *
     * Requirements:
     * - The contract must not be already paused
     */
    function pause() external;

    /**
     * @notice Unpauses the data service.
     * @dev Note that only functions using the modifiers `whenNotPaused`
     * and `whenPaused` will be affected by the pause.
     *
     * Requirements:
     * - The contract must be paused
     */
    function unpause() external;
}
