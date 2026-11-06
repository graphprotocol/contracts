// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L1GraphTokenGatewaySharedTest } from "./L1GraphTokenGatewayShared.t.sol";
import { IL1GraphTokenGatewayLike } from "../interfaces/IL1GraphTokenGatewayLike.sol";

/// Cases from the "immediately after deploy" context: the gateway is paused and unconfigured
contract L1GraphTokenGatewayConfigTest is L1GraphTokenGatewaySharedTest {
    // -- calculateL2TokenAddress --

    function test_CalculateL2TokenAddress_ReturnsZeroWhenNotSet() public view {
        assertEq(l1Gateway.calculateL2TokenAddress(address(grt)), address(0));
    }

    // -- outboundTransfer --

    function test_OutboundTransfer_RevertWhen_Paused() public {
        vm.expectRevert(bytes("Paused (contract)"));
        vm.prank(tokenSender);
        l1Gateway.outboundTransfer{ value: DEFAULT_ETH_VALUE }(
            address(grt),
            l2Receiver,
            10 ether,
            MAX_GAS,
            GAS_PRICE_BID,
            defaultData
        );
    }

    // -- finalizeInboundTransfer --

    function test_FinalizeInboundTransfer_RevertWhen_Paused() public {
        vm.expectRevert(bytes("Paused (contract)"));
        vm.prank(tokenSender);
        l1Gateway.finalizeInboundTransfer(address(grt), l2Receiver, tokenSender, 10 ether, defaultData);
    }

    // -- setArbitrumAddresses --

    function test_SetArbitrumAddresses_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.setArbitrumAddresses(address(inboxMock), routerMock);
    }

    function test_SetArbitrumAddresses_RevertWhen_NotContract() public {
        vm.expectRevert(bytes("INBOX_MUST_BE_CONTRACT"));
        vm.prank(governor);
        l1Gateway.setArbitrumAddresses(tokenSender, routerMock);

        vm.expectRevert(bytes("ROUTER_MUST_BE_CONTRACT"));
        vm.prank(governor);
        l1Gateway.setArbitrumAddresses(address(inboxMock), tokenSender);
    }

    function test_SetArbitrumAddresses_SetsInboxAndRouter() public {
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.ArbitrumAddressesSet(address(inboxMock), routerMock);
        vm.prank(governor);
        l1Gateway.setArbitrumAddresses(address(inboxMock), routerMock);

        assertEq(l1Gateway.l1Router(), routerMock);
        assertEq(l1Gateway.inbox(), address(inboxMock));
    }

    // -- setL2TokenAddress --

    function test_SetL2TokenAddress_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.setL2TokenAddress(l2GRTMock);
    }

    function test_SetL2TokenAddress_SetsL2GRT() public {
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2TokenAddressSet(l2GRTMock);
        vm.prank(governor);
        l1Gateway.setL2TokenAddress(l2GRTMock);

        assertEq(l1Gateway.l2GRT(), l2GRTMock);
    }

    // -- setL2CounterpartAddress --

    function test_SetL2CounterpartAddress_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.setL2CounterpartAddress(l2GatewayMock);
    }

    function test_SetL2CounterpartAddress_SetsL2Counterpart() public {
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.L2CounterpartAddressSet(l2GatewayMock);
        vm.prank(governor);
        l1Gateway.setL2CounterpartAddress(l2GatewayMock);

        assertEq(l1Gateway.l2Counterpart(), l2GatewayMock);
        assertEq(l1Gateway.counterpartGateway(), l2GatewayMock);
    }

    // -- setEscrowAddress --

    function test_SetEscrowAddress_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.setEscrowAddress(address(bridgeEscrow));
    }

    function test_SetEscrowAddress_SetsEscrow() public {
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.EscrowAddressSet(address(bridgeEscrow));
        vm.prank(governor);
        l1Gateway.setEscrowAddress(address(bridgeEscrow));

        assertEq(l1Gateway.escrow(), address(bridgeEscrow));
    }

    // -- addToCallhookAllowlist --

    function test_AddToCallhookAllowlist_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.addToCallhookAllowlist(address(controller));

        assertFalse(l1Gateway.callhookAllowlist(address(controller)));
    }

    function test_AddToCallhookAllowlist_RevertWhen_NotContract() public {
        vm.expectRevert(bytes("MUST_BE_CONTRACT"));
        vm.prank(governor);
        l1Gateway.addToCallhookAllowlist(tokenSender);
    }

    function test_AddToCallhookAllowlist_AddsAddress() public {
        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.AddedToCallhookAllowlist(address(controller));
        vm.prank(governor);
        l1Gateway.addToCallhookAllowlist(address(controller));

        assertTrue(l1Gateway.callhookAllowlist(address(controller)));
    }

    // -- removeFromCallhookAllowlist --

    function test_RemoveFromCallhookAllowlist_RevertWhen_NotGovernor() public {
        vm.prank(governor);
        l1Gateway.addToCallhookAllowlist(address(controller));

        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.removeFromCallhookAllowlist(address(controller));

        assertTrue(l1Gateway.callhookAllowlist(address(controller)));
    }

    function test_RemoveFromCallhookAllowlist_RemovesAddress() public {
        vm.prank(governor);
        l1Gateway.addToCallhookAllowlist(address(controller));

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.RemovedFromCallhookAllowlist(address(controller));
        vm.prank(governor);
        l1Gateway.removeFromCallhookAllowlist(address(controller));

        assertFalse(l1Gateway.callhookAllowlist(address(controller)));
    }

    // -- Pausable behavior --

    function test_PausableBehavior_RevertWhen_NotGovernorOrGuardian() public {
        vm.expectRevert(bytes("Only Governor or Guardian"));
        vm.prank(tokenSender);
        l1Gateway.setPaused(false);

        vm.expectRevert(bytes("Only Governor or Guardian"));
        vm.prank(tokenSender);
        l1Gateway.setPaused(true);
    }

    function test_PausableBehavior_RevertWhen_UnpausingWithStateNotSet() public {
        vm.startPrank(governor);
        vm.expectRevert(bytes("INBOX_NOT_SET"));
        l1Gateway.setPaused(false);

        l1Gateway.setArbitrumAddresses(address(inboxMock), routerMock);
        vm.expectRevert(bytes("L2_COUNTERPART_NOT_SET"));
        l1Gateway.setPaused(false);

        l1Gateway.setL2CounterpartAddress(l2GatewayMock);
        vm.expectRevert(bytes("ESCROW_NOT_SET"));
        l1Gateway.setPaused(false);
        vm.stopPrank();
    }

    function test_PausableBehavior_GovernorCanPauseAndUnpause() public {
        _configureL1Bridge();

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.PauseChanged(true);
        vm.prank(governor);
        l1Gateway.setPaused(true);
        assertTrue(l1Gateway.paused());

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.PauseChanged(false);
        vm.prank(governor);
        l1Gateway.setPaused(false);
        assertFalse(l1Gateway.paused());
    }

    // -- setPauseGuardian --

    function test_SetPauseGuardian_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenSender);
        l1Gateway.setPauseGuardian(pauseGuardian);
    }

    function test_SetPauseGuardian_SetsPauseGuardian() public {
        address currentPauseGuardian = l1Gateway.pauseGuardian();

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.NewPauseGuardian(currentPauseGuardian, pauseGuardian);
        vm.prank(governor);
        l1Gateway.setPauseGuardian(pauseGuardian);
    }

    function test_SetPauseGuardian_GuardianCanPauseAndUnpause() public {
        _configureL1Bridge();
        vm.prank(governor);
        l1Gateway.setPauseGuardian(pauseGuardian);

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.PauseChanged(true);
        vm.prank(pauseGuardian);
        l1Gateway.setPaused(true);
        assertTrue(l1Gateway.paused());

        vm.expectEmit(address(l1Gateway));
        emit IL1GraphTokenGatewayLike.PauseChanged(false);
        vm.prank(pauseGuardian);
        l1Gateway.setPaused(false);
        assertFalse(l1Gateway.paused());
    }
}
