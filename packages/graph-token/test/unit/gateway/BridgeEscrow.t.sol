// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";
import { IBridgeEscrowLike } from "../interfaces/IBridgeEscrowLike.sol";

contract BridgeEscrowTest is ProtocolFixture {
    string internal constant GRAPH_TOKEN = string.concat(PKG_ARTIFACTS, "token/GraphToken.sol/GraphToken.json");
    string internal constant BRIDGE_ESCROW = string.concat(PKG_ARTIFACTS, "gateway/BridgeEscrow.sol/BridgeEscrow.json");

    uint256 internal constant N_TOKENS = 1000 ether;

    IGraphTokenLike internal grt;
    IBridgeEscrowLike internal bridgeEscrow;
    address internal tokenReceiver = makeAddr("tokenReceiver");
    address internal spender = makeAddr("spender");

    function setUp() public {
        vm.warp(1_700_000_000);
        _deployProtocolBase();

        vm.prank(governor);
        grt = IGraphTokenLike(_deployArtifact(GRAPH_TOKEN, abi.encode(10_000_000_000 ether)));
        _registerContract("GraphToken", address(grt));

        address impl = _deployArtifact(BRIDGE_ESCROW, "");
        bridgeEscrow = IBridgeEscrowLike(
            _deployBehindProxy(impl, abi.encodeCall(IBridgeEscrowLike.initialize, (address(controller))))
        );

        // Cache GraphToken in the escrow
        IManaged(address(bridgeEscrow)).syncAllContracts();

        vm.prank(governor);
        grt.mint(address(bridgeEscrow), N_TOKENS);
    }

    function test_ApproveAll_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenReceiver);
        bridgeEscrow.approveAll(spender);
    }

    function test_ApproveAll_AllowsSpenderToTransfer() public {
        assertEq(grt.allowance(address(bridgeEscrow), spender), 0);

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        vm.prank(spender);
        grt.transferFrom(address(bridgeEscrow), tokenReceiver, N_TOKENS);

        vm.prank(governor);
        bridgeEscrow.approveAll(spender);

        vm.expectEmit(address(grt));
        emit IGraphTokenLike.Transfer(address(bridgeEscrow), tokenReceiver, N_TOKENS);
        vm.prank(spender);
        grt.transferFrom(address(bridgeEscrow), tokenReceiver, N_TOKENS);

        assertEq(grt.balanceOf(tokenReceiver), N_TOKENS);
    }

    function test_RevokeAll_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Controller governor"));
        vm.prank(tokenReceiver);
        bridgeEscrow.revokeAll(spender);
    }

    function test_RevokeAll_RevokesSpender() public {
        vm.startPrank(governor);
        bridgeEscrow.approveAll(spender);
        bridgeEscrow.revokeAll(spender);
        vm.stopPrank();

        vm.expectRevert(bytes("ERC20: transfer amount exceeds allowance"));
        vm.prank(spender);
        grt.transferFrom(address(bridgeEscrow), tokenReceiver, 1);
    }
}
