// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

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
 * @dev This contract inherits from {DataService} which needs to be initialized, please see
 * {DataService} for detailed instructions.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
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

    /// @inheritdoc IDataServicePausable
    function pause() external override onlyPauseGuardian {
        _pause();
    }

    /// @inheritdoc IDataServicePausable
    function unpause() external override onlyPauseGuardian {
        _unpause();
    }

    /**
     * @notice Sets a pause guardian.
     * @dev Internal function to be used by the derived contract to set pause guardians.
     * @param _pauseGuardian The address of the pause guardian
     * @param _allowed The allowed status of the pause guardian
     */
    function _setPauseGuardian(address _pauseGuardian, bool _allowed) internal {
        require(
            pauseGuardians[_pauseGuardian] == !_allowed,
            DataServicePausablePauseGuardianNoChange(_pauseGuardian, _allowed)
        );
        pauseGuardians[_pauseGuardian] = _allowed;
        emit PauseGuardianSet(_pauseGuardian, _allowed);
    }
}
