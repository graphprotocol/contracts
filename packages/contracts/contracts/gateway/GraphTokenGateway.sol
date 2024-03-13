// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { Pausable } from "../governance/Pausable.sol";
import { Managed } from "../governance/Managed.sol";

/**
 * @title L1/L2 Graph Token Gateway
 * @dev This includes everything that's shared between the L1 and L2 sides of the bridge.
 */
abstract contract GraphTokenGateway is GraphUpgradeable, Pausable, Managed, ITokenGateway {
    /// @dev Storage gap added in case we need to add state variables to this contract
    uint256[50] private __gap;

    /**
     * @dev Check if the caller is the Controller's governor or this contract's pause guardian.
     */
    modifier onlyGovernorOrGuardian() {
        require(msg.sender == controller.getGovernor() || msg.sender == pauseGuardian, "Only Governor or Guardian");
        _;
    }

    /**
     * @notice Change the Pause Guardian for this contract
     * @param _newPauseGuardian The address of the new Pause Guardian
     */
    function setPauseGuardian(address _newPauseGuardian) external onlyGovernor {
        require(_newPauseGuardian != address(0), "PauseGuardian must be set");
        _setPauseGuardian(_newPauseGuardian);
    }

    /**
     * @notice Change the paused state of the contract
     * @param _newPaused New value for the pause state (true means the transfers will be paused)
     */
    function setPaused(bool _newPaused) external onlyGovernorOrGuardian {
        if (!_newPaused) {
            _checksBeforeUnpause();
        }
        _setPaused(_newPaused);
    }

    /**
     * @notice Getter to access paused state of this contract
     * @return True if the contract is paused, false otherwise
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @dev Override the default pausing from Managed to allow pausing this
     * particular contract instead of pausing from the Controller.
     */
    function _notPaused() internal view override {
        require(!_paused, "Paused (contract)");
    }

    /**
     * @dev Runs state validation before unpausing, reverts if
     * something is not set properly
     */
    function _checksBeforeUnpause() internal view virtual;
}
