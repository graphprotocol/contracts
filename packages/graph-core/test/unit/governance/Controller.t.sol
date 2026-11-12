// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IControllerLike } from "../interfaces/IControllerLike.sol";
import { GraphCoreTest } from "../shared/GraphCoreTest.t.sol";

contract ControllerTest is GraphCoreTest {
    event SetContractProxy(bytes32 indexed id, address contractAddress);
    event SetController(address controller);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed pauseGuardian);

    bytes32 internal constant EPOCH_MANAGER_ID = keccak256("EpochManager");

    address internal me = makeAddr("me");
    address internal mockController = makeAddr("mockController");
    address internal newMockEpochManager = makeAddr("newMockEpochManager");

    function setUp() public override {
        super.setUp();
        _registerContract("EpochManager", address(managed));
    }

    // -- setContractProxy() --

    function test_SetContractProxy_SetsAndGets() public {
        assertEq(address(managed.controller()), address(controller));

        vm.expectEmit(address(controller));
        emit SetContractProxy(EPOCH_MANAGER_ID, newMockEpochManager);
        vm.prank(governor);
        controller.setContractProxy(EPOCH_MANAGER_ID, newMockEpochManager);
        assertEq(controller.getContractProxy(EPOCH_MANAGER_ID), newMockEpochManager);
    }

    function test_SetContractProxy_RevertWhen_AddressZero() public {
        vm.expectRevert(bytes("Contract address must be set"));
        vm.prank(governor);
        controller.setContractProxy(EPOCH_MANAGER_ID, address(0));
    }

    function test_SetContractProxy_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        controller.setContractProxy(EPOCH_MANAGER_ID, newMockEpochManager);
    }

    // -- unsetContractProxy() --

    function test_UnsetContractProxy_Unsets() public {
        vm.prank(governor);
        controller.setContractProxy(EPOCH_MANAGER_ID, newMockEpochManager);
        assertEq(controller.getContractProxy(EPOCH_MANAGER_ID), newMockEpochManager);

        vm.expectEmit(address(controller));
        emit SetContractProxy(EPOCH_MANAGER_ID, address(0));
        vm.prank(governor);
        controller.unsetContractProxy(EPOCH_MANAGER_ID);
        assertEq(controller.getContractProxy(EPOCH_MANAGER_ID), address(0));
    }

    function test_UnsetContractProxy_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        controller.unsetContractProxy(EPOCH_MANAGER_ID);
    }

    // -- updateController() --

    function test_UpdateController_UpdatesManaged() public {
        vm.expectEmit(address(managed));
        emit SetController(mockController);
        vm.prank(governor);
        controller.updateController(EPOCH_MANAGER_ID, mockController);
        assertEq(address(managed.controller()), mockController);
    }

    function test_UpdateController_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        controller.updateController(EPOCH_MANAGER_ID, mockController);
    }

    function test_UpdateController_RevertWhen_ControllerZero() public {
        vm.expectRevert(bytes("Controller must be set"));
        vm.prank(governor);
        controller.updateController(EPOCH_MANAGER_ID, address(0));
    }

    // -- setController() --

    function test_SetController_RevertWhen_NotController() public {
        vm.expectRevert(bytes("Caller must be Controller"));
        vm.prank(me);
        managed.setController(mockController);
    }

    // -- setPauseGuardian() --

    function test_SetPauseGuardian_Sets() public {
        address currentPauseGuardian = IControllerLike(address(controller)).pauseGuardian();
        vm.expectEmit(address(controller));
        emit NewPauseGuardian(currentPauseGuardian, me);
        vm.prank(governor);
        controller.setPauseGuardian(me);
        assertEq(IControllerLike(address(controller)).pauseGuardian(), me);
    }

    function test_SetPauseGuardian_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(me);
        controller.setPauseGuardian(me);
    }

    function test_SetPauseGuardian_RevertWhen_GuardianZero() public {
        vm.expectRevert(bytes("PauseGuardian must be set"));
        vm.prank(governor);
        controller.setPauseGuardian(address(0));
    }
}
