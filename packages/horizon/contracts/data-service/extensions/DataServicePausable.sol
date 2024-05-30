// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServicePausable } from "../interfaces/IDataServicePausable.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { DataService } from "../DataService.sol";

/**
 * @title DataServicePausable contract
 * @dev Implementation of the {IDataServicePausable} interface.
 * @notice Extension for the {IDataService} contract, adds pausing functionality
 * to the data service. Pausing is controlled by privileged accounts called
 * pause guardians.
 * @dev Note that this extension does not provide an external function to set pause
 * guardians. This should be implemented in the derived contract.
 */
abstract contract DataServicePausable is Pausable, DataService, IDataServicePausable {
    /// @notice List of pause guardians and their allowed status
    mapping(address pauseGuardian => bool allowed) public pauseGuardians;

    /**
     * @notice Checks if the caller is a pause guardian.
     */
    modifier onlyPauseGuardian() {
        require(pauseGuardians[msg.sender], DataServicePausableNotPauseGuardian(msg.sender));
        _;
    }

    /**
     * @notice See {IDataServicePausable-pause}
     */
    function pause() external onlyPauseGuardian whenNotPaused {
        _pause();
    }

    /**
     * @notice See {IDataServicePausable-pause}
     */
    function unpause() external onlyPauseGuardian whenPaused {
        _unpause();
    }

    /**
     * @notice Sets a pause guardian.
     * @dev Internal function to be used by the derived contract to set pause guardians.
     *
     * Emits a {PauseGuardianSet} event.
     *
     * @param _pauseGuardian The address of the pause guardian
     * @param _allowed The allowed status of the pause guardian
     */
    function _setPauseGuardian(address _pauseGuardian, bool _allowed) internal whenNotPaused {
        pauseGuardians[_pauseGuardian] = _allowed;
        emit PauseGuardianSet(_pauseGuardian, _allowed);
    }
}
