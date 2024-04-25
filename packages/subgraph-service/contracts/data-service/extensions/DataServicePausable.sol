// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { DataService } from "../DataService.sol";

abstract contract DataServicePausable is Pausable, DataService {
    mapping(address account => bool allowed) public pauseGuardians;

    event PauseGuardianSet(address indexed account, bool allowed);
    error DataServicePausableNotPauseGuardian(address account);

    modifier onlyPauseGuardian() {
        if (!pauseGuardians[msg.sender]) {
            revert DataServicePausableNotPauseGuardian(msg.sender);
        }
        _;
    }

    function pause() public onlyPauseGuardian whenNotPaused {
        _pause();
    }

    function unpause() public onlyPauseGuardian whenPaused {
        _unpause();
    }

    function _setPauseGuardian(address account, bool allowed) internal whenNotPaused {
        pauseGuardians[account] = allowed;
        emit PauseGuardianSet(account, allowed);
    }
}
