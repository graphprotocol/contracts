pragma solidity ^0.6.12;

contract Pausable {
    // Two types of pausing in the protocol
    bool internal _recoveryPaused;
    bool internal _paused;

    // Time last paused for both pauses
    uint256 public lastPauseRecoveryTime;
    uint256 public lastPauseTime;

    // Pause guardian is a separate entity from the governor that can pause
    address public pauseGuardian;

    event RecoveryPauseChanged(bool isPaused);
    event PauseChanged(bool isPaused);
    event NewPauseGuardian(address oldPauseGuardian, address pauseGuardian);

    /**
     * @notice Change the recovery paused state of the contract
     */
    function _setRecoveryPaused(bool _toPause) internal {
        if (_toPause == _recoveryPaused) {
            return;
        }
        _recoveryPaused = _toPause;
        if (_recoveryPaused) {
            lastPauseRecoveryTime = now;
        }
        emit RecoveryPauseChanged(_recoveryPaused);
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
            lastPauseTime = now;
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
