// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";
import { IBridgeEscrowLike } from "../interfaces/IBridgeEscrowLike.sol";
import { IL1GraphTokenGatewayLike } from "../interfaces/IL1GraphTokenGatewayLike.sol";
import { IBridgeMockLike, IInboxMockLike, IOutboxMockLike } from "../interfaces/IArbitrumMocksLike.sol";

abstract contract L1GraphTokenGatewaySharedTest is ProtocolFixture {
    string internal constant GRAPH_TOKEN = "GraphToken.sol:GraphToken";
    string internal constant BRIDGE_ESCROW = "BridgeEscrow.sol:BridgeEscrow";
    string internal constant L1_GATEWAY = "L1GraphTokenGateway.sol:L1GraphTokenGateway";
    string internal constant BRIDGE_MOCK = "BridgeMock.sol:BridgeMock";
    string internal constant INBOX_MOCK = "InboxMock.sol:InboxMock";
    string internal constant OUTBOX_MOCK = "OutboxMock.sol:OutboxMock";

    uint256 internal constant SENDER_TOKENS = 1000 ether;
    uint256 internal constant MAX_GAS = 1_000_000;
    uint256 internal constant MAX_SUBMISSION_COST = 7;
    uint256 internal constant GAS_PRICE_BID = 2;
    uint256 internal constant DEFAULT_ETH_VALUE = MAX_SUBMISSION_COST + MAX_GAS * GAS_PRICE_BID;

    IGraphTokenLike internal grt;
    IBridgeEscrowLike internal bridgeEscrow;
    IL1GraphTokenGatewayLike internal l1Gateway;

    IBridgeMockLike internal bridgeMock;
    IInboxMockLike internal inboxMock;
    IOutboxMockLike internal outboxMock;

    address internal tokenSender = makeAddr("tokenSender");
    address internal l2Receiver = makeAddr("l2Receiver");
    address internal pauseGuardian = makeAddr("pauseGuardian");
    address internal routerMock = makeAddr("routerMock");
    address internal l2GRTMock = makeAddr("l2GRTMock");
    address internal l2GatewayMock = makeAddr("l2GatewayMock");

    bytes internal defaultData = abi.encode(MAX_SUBMISSION_COST, bytes(""));

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        _deployProtocolBase();

        vm.prank(governor);
        grt = IGraphTokenLike(_deployPkg(GRAPH_TOKEN, abi.encode(10_000_000_000 ether)));
        _registerContract("GraphToken", address(grt));

        bridgeEscrow = IBridgeEscrowLike(
            _deployBehindProxy(
                _deployPkg(BRIDGE_ESCROW, ""),
                abi.encodeCall(IBridgeEscrowLike.initialize, (address(controller)))
            )
        );
        IManaged(address(bridgeEscrow)).syncAllContracts();

        l1Gateway = IL1GraphTokenGatewayLike(
            _deployBehindProxy(
                _deployPkg(L1_GATEWAY, ""),
                abi.encodeCall(IL1GraphTokenGatewayLike.initialize, (address(controller)))
            )
        );
        _registerContract("GraphTokenGateway", address(l1Gateway));
        IManaged(address(l1Gateway)).syncAllContracts();

        bridgeMock = IBridgeMockLike(_deployPkg(BRIDGE_MOCK, ""));
        inboxMock = IInboxMockLike(_deployPkg(INBOX_MOCK, ""));
        outboxMock = IOutboxMockLike(_deployPkg(OUTBOX_MOCK, ""));
        bridgeMock.setInbox(address(inboxMock), true);
        bridgeMock.setOutbox(address(outboxMock), true);
        inboxMock.setBridge(address(bridgeMock));
        outboxMock.setBridge(address(bridgeMock));

        vm.etch(routerMock, hex"1234");
        vm.etch(l2GRTMock, hex"1234");
        vm.etch(l2GatewayMock, hex"1234");

        vm.startPrank(governor);
        // As in the old fixture's graph config, the gateway mints what L2 sends beyond the escrow
        grt.addMinter(address(l1Gateway));
        grt.mint(tokenSender, SENDER_TOKENS);
        vm.stopPrank();
        vm.deal(tokenSender, 1 ether);
        vm.deal(routerMock, 1 ether);
    }

    /// Wires the gateway to the L2 mocks, escrow and Arbitrum bridge mocks, then unpauses it
    function _configureL1Bridge() internal {
        vm.startPrank(governor);
        l1Gateway.setL2TokenAddress(l2GRTMock);
        l1Gateway.setL2CounterpartAddress(l2GatewayMock);
        l1Gateway.setEscrowAddress(address(bridgeEscrow));
        bridgeEscrow.approveAll(address(l1Gateway));
        l1Gateway.setArbitrumAddresses(address(inboxMock), routerMock);
        l1Gateway.setPaused(false);
        vm.stopPrank();
    }
}
