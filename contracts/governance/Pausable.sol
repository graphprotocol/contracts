pragma solidity ^0.6.4;

contract Pausable {
    // Two types of pausing in the protocol
    bool public recoveryPaused;
    bool public paused;

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
    function _setRecoveryPaused(bool _recoveryPaused) internal {
        if (_recoveryPaused == recoveryPaused) {
            return;
        }
        recoveryPaused = _recoveryPaused;
        if (recoveryPaused) {
            lastPauseRecoveryTime = now;
        }
        emit RecoveryPauseChanged(recoveryPaused);
    }

    /**
     * @notice Change the paused state of the contract
     */
    function _setPaused(bool _paused) internal {
        if (_paused == paused) {
            return;
        }
        paused = _paused;
        if (paused) {
            lastPauseTime = now;
        }
        emit PauseChanged(paused);
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
