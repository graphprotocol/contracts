// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {HorizonStakingSharedTest} from "../../shared/horizon-staking/HorizonStakingShared.t.sol";
import {DataServiceImpPausable} from "../implementations/DataServiceImpPausable.sol";
import {IDataServicePausable} from "./../../../contracts/data-service/interfaces/IDataServicePausable.sol";

contract DataServicePausableTest is HorizonStakingSharedTest {
    DataServiceImpPausable dataService;

    event Paused(address pauser);
    event Unpaused(address unpauser);

    function setUp() public override {
        super.setUp();

        dataService = new DataServiceImpPausable(address(controller));
    }

    modifier whenTheCallerIsAPauseGuardian() {
        _assert_setPauseGuardian(address(this), true);
        _;
    }

    function test_Pause_WhenTheProtocolIsNotPaused() external whenTheCallerIsAPauseGuardian {
        _assert_pause();
    }

    function test_Pause_RevertWhen_TheProtocolIsPaused() external whenTheCallerIsAPauseGuardian {
        _assert_pause();

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
        _assert_pause();
        _assert_unpause();
    }

    function test_Unpause_RevertWhen_TheProtocolIsNotPaused() external whenTheCallerIsAPauseGuardian {
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        dataService.unpause();
        assertEq(dataService.paused(), false);
    }

    function test_Unpause_RevertWhen_TheCallerIsNotAPauseGuardian() external {
        _assert_setPauseGuardian(address(this), true);
        _assert_pause();
        _assert_setPauseGuardian(address(this), false);

        vm.expectRevert(abi.encodeWithSignature("DataServicePausableNotPauseGuardian(address)", address(this)));
        dataService.unpause();
        assertEq(dataService.paused(), true);
    }

    function test_SetPauseGuardian_WhenSettingAPauseGuardian() external {
        _assert_setPauseGuardian(address(this), true);
    }

    function test_SetPauseGuardian_WhenRemovingAPauseGuardian() external {
        _assert_setPauseGuardian(address(this), true);
        _assert_setPauseGuardian(address(this), false);
    }

    function _assert_pause() private {
        vm.expectEmit();
        emit Paused(address(this));
        dataService.pause();
        assertEq(dataService.paused(), true);
    }

    function _assert_unpause() private {
        vm.expectEmit();
        emit Unpaused(address(this));
        dataService.unpause();
        assertEq(dataService.paused(), false);
    }

    function _assert_setPauseGuardian(address pauseGuardian, bool allowed) private {
        vm.expectEmit();
        emit IDataServicePausable.PauseGuardianSet(pauseGuardian, allowed);
        dataService.setPauseGuardian(pauseGuardian, allowed);
        assertEq(dataService.pauseGuardians(pauseGuardian), allowed);
    }
}
