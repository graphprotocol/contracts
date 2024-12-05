// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IDataServicePausable } from "../interfaces/IDataServicePausable.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { DataService } from "../DataService.sol";

/**
 * @title DataServicePausableUpgradeable contract
 * @dev Implementation of the {IDataServicePausable} interface.
 * @dev Upgradeable version of the {DataServicePausable} contract.
 * @dev This contract inherits from {DataService} which needs to be initialized, please see
 * {DataService} for detailed instructions.
 */
abstract contract DataServicePausableUpgradeable is PausableUpgradeable, DataService, IDataServicePausable {
    /// @notice List of pause guardians and their allowed status
    mapping(address pauseGuardian => bool allowed) public pauseGuardians;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;

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
    function pause() external override onlyPauseGuardian whenNotPaused {
        _pause();
    }

    /**
     * @notice See {IDataServicePausable-pause}
     */
    function unpause() external override onlyPauseGuardian whenPaused {
        _unpause();
    }

    /**
     * @notice Initializes the contract and parent contracts
     */
    // solhint-disable-next-line func-name-mixedcase
    function __DataServicePausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
        __DataServicePausable_init_unchained();
    }

    /**
     * @notice Initializes the contract
     */
    // solhint-disable-next-line func-name-mixedcase
    function __DataServicePausable_init_unchained() internal onlyInitializing {}

    /**
     * @notice Sets a pause guardian.
     * @dev Internal function to be used by the derived contract to set pause guardians.
     *
     * Emits a {PauseGuardianSet} event.
     *
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
