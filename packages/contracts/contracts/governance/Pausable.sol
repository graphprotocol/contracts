// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

abstract contract Pausable {
    /**
     * @dev "Partial paused" pauses exit and enter functions for GRT, but not internal
     * functions, such as allocating
     */
    bool internal _partialPaused;
    /**
     * @dev Paused will pause all major protocol functions
     */
    bool internal _paused;

    /// Timestamp for the last time the partial pause was set
    uint256 public lastPartialPauseTime;
    /// Timestamp for the last time the full pause was set
    uint256 public lastPauseTime;

    /// Pause guardian is a separate entity from the governor that can
    /// pause and unpause the protocol, fully or partially
    address public pauseGuardian;

    /// Emitted when the partial pause state changed
    event PartialPauseChanged(bool isPaused);
    /// Emitted when the full pause state changed
    event PauseChanged(bool isPaused);
    /// Emitted when the pause guardian is changed
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    /**
     * @dev Change the partial paused state of the contract
     * @param _toPartialPause New value for the partial pause state (true means the contracts will be partially paused)
     */
    function _setPartialPaused(bool _toPartialPause) internal {
        if (_toPartialPause == _partialPaused) {
            return;
        }
        _partialPaused = _toPartialPause;
        if (_partialPaused) {
            lastPartialPauseTime = block.timestamp;
        }
        emit PartialPauseChanged(_partialPaused);
    }

    /**
     * @dev Change the paused state of the contract
     * @param _toPause New value for the pause state (true means the contracts will be paused)
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
     * @dev Change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function _setPauseGuardian(address newPauseGuardian) internal {
        address oldPauseGuardian = pauseGuardian;
        pauseGuardian = newPauseGuardian;
        emit NewPauseGuardian(oldPauseGuardian, newPauseGuardian);
    }
}
