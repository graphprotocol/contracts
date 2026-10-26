// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2GraphTokenGatewaySharedTest } from "./L2GraphTokenGatewayShared.t.sol";
import { IL2GraphTokenGatewayLike } from "../interfaces/IL2GraphTokenGatewayLike.sol";

/// Cases from the "immediately after deploy" context: the gateway is paused and unconfigured
contract L2GraphTokenGatewayConfigTest is L2GraphTokenGatewaySharedTest {
    // -- calculateL2TokenAddress --

    function test_CalculateL2TokenAddress_ReturnsZeroWhenNotSet() public view {
        assertEq(l2Gateway.calculateL2TokenAddress(address(grt)), address(0));
    }

    // -- outboundTransfer --

    function test_OutboundTransfer_RevertWhen_Paused() public {
        vm.expectRevert(bytes("Paused (contract)"));
        vm.prank(tokenSender);
        l2Gateway.outboundTransfer(address(grt), l1Receiver, 10 ether, defaultData);
    }

    // -- finalizeInboundTransfer --

    function test_FinalizeInboundTransfer_RevertWhen_Paused() public {
        vm.expectRevert(bytes("Paused (contract)"));
        vm.prank(tokenSender);
        l2Gateway.finalizeInboundTransfer(address(grt), tokenSender, l1Receiver, 10 ether, defaultData);
    }

    // -- setL2Router --

    function test_SetL2Router_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l2Gateway.setL2Router(routerMock);
    }

    function test_SetL2Router_SetsRouter() public {
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.L2RouterSet(routerMock);
        vm.prank(governor);
        l2Gateway.setL2Router(routerMock);

        assertEq(l2Gateway.l2Router(), routerMock);
    }

    // -- setL1TokenAddress --

    function test_SetL1TokenAddress_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l2Gateway.setL1TokenAddress(l1GRTMock);
    }

    function test_SetL1TokenAddress_SetsL1GRT() public {
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.L1TokenAddressSet(l1GRTMock);
        vm.prank(governor);
        l2Gateway.setL1TokenAddress(l1GRTMock);

        assertEq(l2Gateway.l1GRT(), l1GRTMock);
    }

    // -- setL1CounterpartAddress --

    function test_SetL1CounterpartAddress_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l2Gateway.setL1CounterpartAddress(l1GatewayMock);
    }

    function test_SetL1CounterpartAddress_SetsL1Counterpart() public {
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.L1CounterpartAddressSet(l1GatewayMock);
        vm.prank(governor);
        l2Gateway.setL1CounterpartAddress(l1GatewayMock);

        assertEq(l2Gateway.l1Counterpart(), l1GatewayMock);
    }

    // -- Pausable behavior --

    function test_PausableBehavior_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(bytes("Only Governor or Guardian"));
        vm.prank(tokenSender);
        l2Gateway.setPaused(false);

        vm.expectRevert(bytes("Only Governor or Guardian"));
        vm.prank(tokenSender);
        l2Gateway.setPaused(true);
    }

    function test_PausableBehavior_RevertWhen_UnpausingWithStateNotSet() public {
        vm.startPrank(governor);
        vm.expectRevert(bytes("L2_ROUTER_NOT_SET"));
        l2Gateway.setPaused(false);

        l2Gateway.setL2Router(routerMock);
        vm.expectRevert(bytes("L1_COUNTERPART_NOT_SET"));
        l2Gateway.setPaused(false);

        l2Gateway.setL1CounterpartAddress(l1GatewayMock);
        vm.expectRevert(bytes("L1_GRT_NOT_SET"));
        l2Gateway.setPaused(false);
        vm.stopPrank();
    }

    function test_PausableBehavior_GovernorCanPauseAndUnpause() public {
        _configureL2Bridge();

        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.PauseChanged(true);
        vm.prank(governor);
        l2Gateway.setPaused(true);
        assertTrue(l2Gateway.paused());

        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.PauseChanged(false);
        vm.prank(governor);
        l2Gateway.setPaused(false);
        assertFalse(l2Gateway.paused());
    }

    // -- setPauseGuardian --

    function test_SetPauseGuardian_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l2Gateway.setPauseGuardian(pauseGuardian);
    }

    function test_SetPauseGuardian_SetsPauseGuardian() public {
        address currentPauseGuardian = l2Gateway.pauseGuardian();

        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.NewPauseGuardian(currentPauseGuardian, pauseGuardian);
        vm.prank(governor);
        l2Gateway.setPauseGuardian(pauseGuardian);
    }

    function test_SetPauseGuardian_GuardianCanPauseAndUnpause() public {
        _configureL2Bridge();
        vm.prank(governor);
        l2Gateway.setPauseGuardian(pauseGuardian);

        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.PauseChanged(true);
        vm.prank(pauseGuardian);
        l2Gateway.setPaused(true);
        assertTrue(l2Gateway.paused());

        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.PauseChanged(false);
        vm.prank(pauseGuardian);
        l2Gateway.setPaused(false);
        assertFalse(l2Gateway.paused());
    }
}
