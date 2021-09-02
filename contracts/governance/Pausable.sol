// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

contract Pausable {
    // Partial paused paused exit and enter functions for GRT, but not internal
    // functions, such as allocating
    bool internal _partialPaused;
    // Paused will pause all major protocol functions
    bool internal _paused;

    // Time last paused for both pauses
    uint256 public lastPausePartialTime;
    uint256 public lastPauseTime;

    // Pause guardian is a separate entity from the governor that can pause
    address public pauseGuardian;

    event PartialPauseChanged(bool isPaused);
    event PauseChanged(bool isPaused);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    /**
     * @notice Change the partial paused state of the contract
     */
    function _setPartialPaused(bool _toPause) internal {
        if (_toPause == _partialPaused) {
            return;
        }
        _partialPaused = _toPause;
        if (_partialPaused) {
            lastPausePartialTime = block.timestamp;
        }
        emit PartialPauseChanged(_partialPaused);
    }

    /**
     * @notice Change the paused state of the contract
     */
    function _setPaused(bool _toPause) internal {
        if (_toPause == _paused) {
            return;
        }
        _paused = _toPause;
        if (_paused) {
            lastPauseTime = block.timestamp;
        }
        emit PauseChanged(_paused);
    }

    /**
     * @notice Change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function _setPauseGuardian(address newPauseGuardian) internal {
        address oldPauseGuardian = pauseGuardian;
        pauseGuardian = newPauseGuardian;
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }
}
