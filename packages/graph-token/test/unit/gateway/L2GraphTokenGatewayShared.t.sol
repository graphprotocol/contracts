// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IL2GraphTokenLike } from "../interfaces/IL2GraphTokenLike.sol";
import { IL2GraphTokenGatewayLike } from "../interfaces/IL2GraphTokenGatewayLike.sol";

abstract contract L2GraphTokenGatewaySharedTest is ProtocolFixture {
    string internal constant L2_GRAPH_TOKEN =
        string.concat(PKG_ARTIFACTS, "l2/token/L2GraphToken.sol/L2GraphToken.json");
    string internal constant L2_GATEWAY =
        string.concat(PKG_ARTIFACTS, "l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json");
    string internal constant CALLHOOK_RECEIVER_MOCK =
        string.concat(PKG_ARTIFACTS, "tests/CallhookReceiverMock.sol/CallhookReceiverMock.json");

    address internal constant ARB_SYS = address(0x64);
    uint256 internal constant SENDER_TOKENS = 1000 ether;

    IL2GraphTokenLike internal grt;
    IL2GraphTokenGatewayLike internal l2Gateway;
    address internal callhookReceiverMock;

    address internal tokenSender = makeAddr("tokenSender");
    address internal l1Receiver = makeAddr("l1Receiver");
    address internal l2Receiver = makeAddr("l2Receiver");
    address internal pauseGuardian = makeAddr("pauseGuardian");
    address internal routerMock = makeAddr("routerMock");
    address internal l1GRTMock = makeAddr("l1GRTMock");
    address internal l1GatewayMock = makeAddr("l1GatewayMock");

    bytes internal defaultData = "";

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        _deployProtocolBase();

        grt = IL2GraphTokenLike(
            _deployBehindProxy(
                _deployArtifact(L2_GRAPH_TOKEN, ""),
                abi.encodeCall(IL2GraphTokenLike.initialize, (governor))
            )
        );
        _registerContract("GraphToken", address(grt));

        l2Gateway = IL2GraphTokenGatewayLike(
            _deployBehindProxy(
                _deployArtifact(L2_GATEWAY, ""),
                abi.encodeCall(IL2GraphTokenGatewayLike.initialize, (address(controller)))
            )
        );
        _registerContract("GraphTokenGateway", address(l2Gateway));
        IManaged(address(l2Gateway)).syncAllContracts();

        callhookReceiverMock = _deployArtifact(CALLHOOK_RECEIVER_MOCK, "");

        vm.etch(routerMock, hex"1234");
        vm.etch(l1GRTMock, hex"1234");
        vm.etch(l1GatewayMock, hex"1234");

        // ArbSys precompile: code so the extcodesize check passes, and sendTxToL1 returns id 1
        vm.etch(ARB_SYS, hex"00");
        vm.mockCall(ARB_SYS, abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)));

        vm.prank(governor);
        grt.mint(tokenSender, SENDER_TOKENS);
    }

    /// Wires the gateway and token to the L1 mocks and router, then unpauses the gateway
    function _configureL2Bridge() internal {
        vm.startPrank(governor);
        l2Gateway.setL1TokenAddress(l1GRTMock);
        grt.setL1Address(l1GRTMock);
        l2Gateway.setL1CounterpartAddress(l1GatewayMock);
        l2Gateway.setL2Router(routerMock);
        grt.setGateway(address(l2Gateway));
        l2Gateway.setPaused(false);
        vm.stopPrank();
    }
}
