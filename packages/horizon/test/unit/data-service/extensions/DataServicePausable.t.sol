// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import { DataServiceImpPausable } from "../implementations/DataServiceImpPausable.sol";
import { IDataServicePausable } from "@graphprotocol/interfaces/contracts/data-service/IDataServicePausable.sol";

contract DataServicePausableTest is HorizonStakingSharedTest {
    DataServiceImpPausable dataService;

    event Paused(address pauser);
    event Unpaused(address unpauser);

    function setUp() public override {
        super.setUp();

        dataService = new DataServiceImpPausable(address(controller));
    }

    modifier whenTheCallerIsAPauseGuardian() {
        _assertSetPauseGuardian(address(this), true);
        _;
    }

    function test_Pause_WhenTheProtocolIsNotPaused() external whenTheCallerIsAPauseGuardian {
        _assertPause();
    }

    function test_Pause_RevertWhen_TheProtocolIsPaused() external whenTheCallerIsAPauseGuardian {
        _assertPause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        dataService.pause();
        assertEq(dataService.paused(), true);
    }

    function test_Pause_RevertWhen_TheCallerIsNotAPauseGuardian() external {
        vm.expectRevert(abi.encodeWithSignature("DataServicePausableNotPauseGuardian(address)", address(this)));
        dataService.pause();
        assertEq(dataService.paused(), false);
    }

    function test_Unpause_WhenTheProtocolIsPaused() external whenTheCallerIsAPauseGuardian {
        _assertPause();
        _assertUnpause();
    }

    function test_Unpause_RevertWhen_TheProtocolIsNotPaused() external whenTheCallerIsAPauseGuardian {
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        dataService.unpause();
        assertEq(dataService.paused(), false);
    }

    function test_Unpause_RevertWhen_TheCallerIsNotAPauseGuardian() external {
        _assertSetPauseGuardian(address(this), true);
        _assertPause();
        _assertSetPauseGuardian(address(this), false);

        vm.expectRevert(abi.encodeWithSignature("DataServicePausableNotPauseGuardian(address)", address(this)));
        dataService.unpause();
        assertEq(dataService.paused(), true);
    }

    function test_SetPauseGuardian_WhenSettingAPauseGuardian() external {
        _assertSetPauseGuardian(address(this), true);
    }

    function test_SetPauseGuardian_WhenRemovingAPauseGuardian() external {
        _assertSetPauseGuardian(address(this), true);
        _assertSetPauseGuardian(address(this), false);
    }

    function test_SetPauseGuardian_RevertWhen_AlreadyPauseGuardian() external {
        _assertSetPauseGuardian(address(this), true);
        vm.expectRevert(
            abi.encodeWithSignature("DataServicePausablePauseGuardianNoChange(address,bool)", address(this), true)
        );
        dataService.setPauseGuardian(address(this), true);
    }

    function test_SetPauseGuardian_RevertWhen_AlreadyNotPauseGuardian() external {
        _assertSetPauseGuardian(address(this), true);
        _assertSetPauseGuardian(address(this), false);
        vm.expectRevert(
            abi.encodeWithSignature("DataServicePausablePauseGuardianNoChange(address,bool)", address(this), false)
        );
        dataService.setPauseGuardian(address(this), false);
    }

    function test_PausedProtectedFn_RevertWhen_TheProtocolIsPaused() external {
        _assertSetPauseGuardian(address(this), true);
        _assertPause();

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        dataService.pausedProtectedFn();
    }

    function test_PausedProtectedFn_WhenTheProtocolIsNotPaused() external {
        vm.expectEmit();
        emit DataServiceImpPausable.PausedProtectedFn();
        dataService.pausedProtectedFn();
    }

    function test_UnpausedProtectedFn_WhenTheProtocolIsPaused() external {
        _assertSetPauseGuardian(address(this), true);
        _assertPause();

        vm.expectEmit();
        emit DataServiceImpPausable.UnpausedProtectedFn();
        dataService.unpausedProtectedFn();
    }

    function test_UnpausedProtectedFn_RevertWhen_TheProtocolIsNotPaused() external {
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        dataService.unpausedProtectedFn();
    }

    function _assertPause() private {
        vm.expectEmit();
        emit Paused(address(this));
        dataService.pause();
        assertEq(dataService.paused(), true);
    }

    function _assertUnpause() private {
        vm.expectEmit();
        emit Unpaused(address(this));
        dataService.unpause();
        assertEq(dataService.paused(), false);
    }

    function _assertSetPauseGuardian(address pauseGuardian, bool allowed) private {
        vm.expectEmit();
        emit IDataServicePausable.PauseGuardianSet(pauseGuardian, allowed);
        dataService.setPauseGuardian(pauseGuardian, allowed);
        assertEq(dataService.pauseGuardians(pauseGuardian), allowed);
    }
}
