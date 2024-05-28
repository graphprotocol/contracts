// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IDataServicePausable } from "../interfaces/IDataServicePausable.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { DataService } from "../DataService.sol";

abstract contract DataServicePausableUpgradeable is PausableUpgradeable, DataService, IDataServicePausable {
    mapping(address pauseGuardian => bool allowed) public pauseGuardians;

    modifier onlyPauseGuardian() {
        require(pauseGuardians[msg.sender], DataServicePausableNotPauseGuardian(msg.sender));
        _;
    }

    function pause() external onlyPauseGuardian whenNotPaused {
        _pause();
    }

    function unpause() external onlyPauseGuardian whenPaused {
        _unpause();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __DataServicePausable_init() internal {
        __Pausable_init_unchained();
        __DataServicePausable_init_unchained();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __DataServicePausable_init_unchained() internal {}

    function _setPauseGuardian(address _pauseGuardian, bool _allowed) internal whenNotPaused {
        pauseGuardians[_pauseGuardian] = _allowed;
        emit PauseGuardianSet(_pauseGuardian, _allowed);
    }
}
