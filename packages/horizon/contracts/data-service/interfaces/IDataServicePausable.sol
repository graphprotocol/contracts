// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataService } from "./IDataService.sol";

/**
 * @title Interface for the {DataServicePausable} contract.
 * @notice Extension for the {IDataService} contract, adds pausing functionality
 * to the data service. Pausing is controlled by privileged accounts called
 * pause guardians.
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
