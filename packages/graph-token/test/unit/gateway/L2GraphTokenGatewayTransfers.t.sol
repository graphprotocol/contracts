// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITokenGateway } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/ITokenGateway.sol";
import { L2GraphTokenGatewaySharedTest } from "./L2GraphTokenGatewayShared.t.sol";
import { IL2GraphTokenLike } from "../interfaces/IL2GraphTokenLike.sol";
import { IL2GraphTokenGatewayLike } from "../interfaces/IL2GraphTokenGatewayLike.sol";
import { ICallhookReceiverMockLike } from "../interfaces/IArbitrumMocksLike.sol";
import { NoCallhookReceiver } from "../mocks/NoCallhookReceiver.sol";

/// Cases from the "after configuring and unpausing" context
contract L2GraphTokenGatewayTransfersTest is L2GraphTokenGatewaySharedTest {
    uint160 internal constant L1_TO_L2_ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);
    uint256 internal constant CALLHOOK_FOO = 1337;
    uint256 internal constant CALLHOOK_BAR = 42;

    bytes internal defaultDataWithNotEmptyCallHookData = abi.encode(CALLHOOK_FOO, CALLHOOK_BAR);

    function setUp() public override {
        super.setUp();
        _configureL2Bridge();
    }

    function _l1GatewayAlias() internal view returns (address) {
        unchecked {
            return address(uint160(l1GatewayMock) + L1_TO_L2_ALIAS_OFFSET);
        }
    }

    function _testValidOutboundTransfer(address signer, bytes memory data) internal {
        uint256 expectedId = 1;
        // Should use the L1 gateway's interface, but both come from ITokenGateway
        bytes memory calldataToL1 = abi.encodeCall(
            ITokenGateway.finalizeInboundTransfer,
            (l1GRTMock, tokenSender, l1Receiver, 10 ether, abi.encode(uint256(0), bytes("")))
        );
        assertEq(l2Gateway.getOutboundCalldata(l1GRTMock, tokenSender, l1Receiver, 10 ether, ""), calldataToL1);

        vm.expectCall(ARB_SYS, abi.encodeWithSignature("sendTxToL1(address,bytes)", l1GatewayMock, calldataToL1));
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.TxToL1(tokenSender, l1GatewayMock, expectedId, calldataToL1);
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.WithdrawalInitiated(l1GRTMock, tokenSender, l1Receiver, expectedId, 0, 10 ether);
        vm.prank(signer);
        l2Gateway.outboundTransfer(l1GRTMock, l1Receiver, 10 ether, data);

        assertEq(grt.balanceOf(tokenSender), 990 ether);
    }

    /// Finalizes a 10 GRT deposit to `to` as the aliased L1 gateway. With `expectCallhook`,
    /// `to` must emit the CallhookReceiverMock event for CALLHOOK_FOO and CALLHOOK_BAR.
    function _testValidFinalizeTransfer(bytes memory data, address to, bool expectCallhook) internal {
        vm.expectEmit(address(grt));
        emit IL2GraphTokenLike.BridgeMinted(to, 10 ether);
        if (expectCallhook) {
            vm.expectEmit(to);
            emit ICallhookReceiverMockLike.TransferReceived(tokenSender, 10 ether, CALLHOOK_FOO, CALLHOOK_BAR);
        }
        vm.expectEmit(address(l2Gateway));
        emit IL2GraphTokenGatewayLike.DepositFinalized(l1GRTMock, tokenSender, to, 10 ether);
        vm.prank(_l1GatewayAlias());
        l2Gateway.finalizeInboundTransfer(l1GRTMock, tokenSender, to, 10 ether, data);

        // Unchanged
        assertEq(grt.balanceOf(tokenSender), 1000 ether);
        // 10 newly minted GRT
        assertEq(grt.balanceOf(to), 10 ether);
    }

    // -- calculateL2TokenAddress --

    function test_CalculateL2TokenAddress_ReturnsL2TokenAddress() public view {
        assertEq(l2Gateway.calculateL2TokenAddress(l1GRTMock), address(grt));
    }

    function test_CalculateL2TokenAddress_ReturnsZeroForOtherAddress() public view {
        assertEq(l2Gateway.calculateL2TokenAddress(tokenSender), address(0));
    }

    // -- outboundTransfer --

    function test_OutboundTransfer_RevertWhen_WrongToken() public {
        vm.expectRevert(bytes("TOKEN_NOT_GRT"));
        vm.prank(tokenSender);
        l2Gateway.outboundTransfer(tokenSender, l1Receiver, 10 ether, defaultData);
    }

    function test_OutboundTransfer_BurnsTokensAndTriggersL1Call() public {
        vm.prank(tokenSender);
        grt.approve(address(l2Gateway), 10 ether);
        _testValidOutboundTransfer(tokenSender, defaultData);
    }

    function test_OutboundTransfer_DecodesSenderFromRouter() public {
        vm.prank(tokenSender);
        grt.approve(address(l2Gateway), 10 ether);
        bytes memory routerEncodedData = abi.encode(tokenSender, defaultData);
        _testValidOutboundTransfer(routerMock, routerEncodedData);
    }

    function test_OutboundTransfer_RevertWhen_NonEmptyCallhookData() public {
        vm.prank(tokenSender);
        grt.approve(address(l2Gateway), 10 ether);

        vm.expectRevert(bytes("CALL_HOOK_DATA_NOT_ALLOWED"));
        vm.prank(tokenSender);
        l2Gateway.outboundTransfer(l1GRTMock, l1Receiver, 10 ether, defaultDataWithNotEmptyCallHookData);
    }

    function test_OutboundTransfer_RevertWhen_InsufficientBalance() public {
        vm.prank(tokenSender);
        grt.approve(address(l2Gateway), 1001 ether);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        vm.prank(tokenSender);
        l2Gateway.outboundTransfer(l1GRTMock, l1Receiver, 1001 ether, defaultData);
    }

    // -- finalizeInboundTransfer --

    function test_FinalizeInboundTransfer_RevertWhen_NotGateway() public {
        vm.expectRevert(bytes("ONLY_COUNTERPART_GATEWAY"));
        vm.prank(tokenSender);
        l2Gateway.finalizeInboundTransfer(l1GRTMock, tokenSender, l2Receiver, 10 ether, defaultData);
    }

    function test_FinalizeInboundTransfer_RevertWhen_GatewayWithoutL2Alias() public {
        vm.expectRevert(bytes("ONLY_COUNTERPART_GATEWAY"));
        vm.prank(l1GatewayMock);
        l2Gateway.finalizeInboundTransfer(l1GRTMock, tokenSender, l2Receiver, 10 ether, defaultData);
    }

    function test_FinalizeInboundTransfer_MintsWhenCalledByAliasedGateway() public {
        _testValidFinalizeTransfer(defaultData, l2Receiver, false);
    }

    function test_FinalizeInboundTransfer_CallsCallhookWithCalldata() public {
        _testValidFinalizeTransfer(defaultDataWithNotEmptyCallHookData, callhookReceiverMock, true);
    }

    function test_FinalizeInboundTransfer_RevertWhen_CallhookReverts() public {
        // A zero foo makes CallhookReceiverMock revert
        bytes memory callHookData = abi.encode(uint256(0), CALLHOOK_BAR);

        vm.expectRevert(bytes("FOO_IS_ZERO"));
        vm.prank(_l1GatewayAlias());
        l2Gateway.finalizeInboundTransfer(l1GRTMock, tokenSender, callhookReceiverMock, 10 ether, callHookData);
    }

    function test_FinalizeInboundTransfer_RevertWhen_ReceiverHasNoCallhook() public {
        address receiver = address(new NoCallhookReceiver());
        bytes memory callHookData = abi.encode(uint256(0));

        // The revert reason depends on the environment
        vm.expectRevert();
        vm.prank(_l1GatewayAlias());
        l2Gateway.finalizeInboundTransfer(l1GRTMock, tokenSender, receiver, 10 ether, callHookData);
    }
}
