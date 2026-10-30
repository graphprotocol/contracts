// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IControllerLike } from "../interfaces/IControllerLike.sol";
import { GraphCoreTest } from "../shared/GraphCoreTest.t.sol";

contract PausingTest is GraphCoreTest {
    event PartialPauseChanged(bool isPaused);
    event PauseChanged(bool isPaused);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    address internal me = makeAddr("me");
    address internal guardian = makeAddr("guardian");

    function _setPartialPause(address account, bool value) internal {
        vm.expectEmit(address(controller));
        emit PartialPauseChanged(value);
        vm.prank(account);
        controller.setPartialPaused(value);
        assertEq(controller.partialPaused(), value);
    }

    function _setPause(address account, bool value) internal {
        vm.expectEmit(address(controller));
        emit PauseChanged(value);
        vm.prank(account);
        controller.setPaused(value);
        assertEq(controller.paused(), value);
    }

    function test_Pausing_SetPauseGuardian() public {
        address currentGuardian = IControllerLike(address(controller)).pauseGuardian();
        vm.expectEmit(address(controller));
        emit NewPauseGuardian(currentGuardian, guardian);
        vm.prank(governor);
        controller.setPauseGuardian(guardian);
        assertEq(IControllerLike(address(controller)).pauseGuardian(), guardian);
    }

    function test_Pausing_RevertWhen_SetPauseGuardianNotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        controller.setPauseGuardian(guardian);
    }

    function test_Pausing_SetAndUnsetPartialPaused() public {
        assertFalse(controller.partialPaused());
        _setPartialPause(governor, true);
        _setPartialPause(governor, false);

        vm.prank(governor);
        controller.setPauseGuardian(guardian);
        _setPartialPause(guardian, true);
        _setPartialPause(guardian, false);
    }

    function test_Pausing_RevertWhen_PartialPauseNotGovernorOrGuardian() public {
        vm.expectRevert(bytes("Only Governor or Guardian can call"));
        vm.prank(me);
        controller.setPartialPaused(true);
    }

    function test_Pausing_RevertWhen_PartialPaused() public {
        _setPartialPause(governor, true);

        vm.expectRevert(bytes("Partial-paused"));
        vm.prank(me);
        managed.checkNotPartialPaused();
    }

    function test_Pausing_SetAndUnsetPaused() public {
        assertFalse(controller.paused());
        _setPause(governor, true);
        _setPause(governor, false);

        vm.prank(governor);
        controller.setPauseGuardian(guardian);
        _setPause(guardian, true);
        _setPause(guardian, false);
    }

    function test_Pausing_RevertWhen_PauseNotGovernorOrGuardian() public {
        vm.expectRevert(bytes("Only Governor or Guardian can call"));
        vm.prank(me);
        controller.setPaused(true);
    }

    function test_Pausing_RevertWhen_Paused() public {
        _setPause(governor, true);

        vm.expectRevert(bytes("Paused"));
        vm.prank(me);
        managed.checkNotPartialPaused();

        vm.expectRevert(bytes("Paused"));
        vm.prank(me);
        managed.checkNotPaused();
    }
}
