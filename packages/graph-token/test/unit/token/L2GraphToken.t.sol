// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GraphTokenSharedTest } from "./GraphTokenShared.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";
import { IL2GraphTokenLike } from "../interfaces/IL2GraphTokenLike.sol";

contract L2GraphTokenTest is GraphTokenSharedTest {
    string internal constant L2_GRAPH_TOKEN =
        string.concat(PKG_ARTIFACTS, "l2/token/L2GraphToken.sol/L2GraphToken.json");

    IL2GraphTokenLike internal grt;
    address internal mockL2Gateway = makeAddr("mockL2Gateway");
    address internal mockL1GRT = makeAddr("mockL1GRT");
    address internal user = makeAddr("user");

    function setUp() public {
        vm.warp(1_700_000_000);
        _deployProtocolBase();
        address impl = _deployArtifact(L2_GRAPH_TOKEN, "");
        grt = IL2GraphTokenLike(_deployBehindProxy(impl, abi.encodeCall(IL2GraphTokenLike.initialize, (governor))));
        _setUpShared();
    }

    function _token() internal view override returns (IGraphTokenLike) {
        return grt;
    }

    function _salt() internal pure override returns (bytes32) {
        return L2_SALT;
    }

    function _configureBridge() internal {
        vm.startPrank(governor);
        grt.setL1Address(mockL1GRT);
        grt.setGateway(mockL2Gateway);
        vm.stopPrank();
    }

    // -- setGateway --

    function test_SetGateway_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(mockL2Gateway);
        grt.setGateway(mockL2Gateway);
    }

    function test_SetGateway_SetsGateway() public {
        vm.expectEmit(address(grt));
        emit IL2GraphTokenLike.GatewaySet(mockL2Gateway);
        vm.prank(governor);
        grt.setGateway(mockL2Gateway);

        assertEq(grt.gateway(), mockL2Gateway);
    }

    // -- setL1Address --

    function test_SetL1Address_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(mockL2Gateway);
        grt.setL1Address(mockL1GRT);
    }

    function test_SetL1Address_SetsL1Address() public {
        vm.expectEmit(address(grt));
        emit IL2GraphTokenLike.L1AddressSet(mockL1GRT);
        vm.prank(governor);
        grt.setL1Address(mockL1GRT);

        assertEq(grt.l1Address(), mockL1GRT);
    }

    // -- bridgeMint --

    function test_BridgeMint_RevertWhen_NotGateway() public {
        _configureBridge();

        vm.expectRevert(bytes("NOT_GATEWAY"));
        vm.prank(governor);
        grt.bridgeMint(user, 100 ether);
    }

    function test_BridgeMint_MintsToAccount() public {
        _configureBridge();

        vm.expectEmit(address(grt));
        emit IL2GraphTokenLike.BridgeMinted(user, 100 ether);
        vm.prank(mockL2Gateway);
        grt.bridgeMint(user, 100 ether);

        assertEq(grt.balanceOf(user), 100 ether);
    }

    // -- bridgeBurn --

    function test_BridgeBurn_RevertWhen_NotGateway() public {
        _configureBridge();

        vm.expectRevert(bytes("NOT_GATEWAY"));
        vm.prank(governor);
        grt.bridgeBurn(user, 100 ether);
    }

    function test_BridgeBurn_RevertWhen_NotApproved() public {
        _configureBridge();
        vm.prank(mockL2Gateway);
        grt.bridgeMint(user, 100 ether);

        vm.expectRevert(bytes("ERC20: burn amount exceeds allowance"));
        vm.prank(mockL2Gateway);
        grt.bridgeBurn(user, 20 ether);
    }

    function test_BridgeBurn_RevertWhen_InsufficientBalance() public {
        _configureBridge();
        vm.prank(mockL2Gateway);
        grt.bridgeMint(user, 10 ether);
        vm.prank(user);
        grt.approve(mockL2Gateway, 20 ether);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        vm.prank(mockL2Gateway);
        grt.bridgeBurn(user, 20 ether);
    }

    function test_BridgeBurn_BurnsWhenApproved() public {
        _configureBridge();
        vm.prank(mockL2Gateway);
        grt.bridgeMint(user, 100 ether);
        vm.prank(user);
        grt.approve(mockL2Gateway, 20 ether);

        vm.expectEmit(address(grt));
        emit IL2GraphTokenLike.BridgeBurned(user, 20 ether);
        vm.prank(mockL2Gateway);
        grt.bridgeBurn(user, 20 ether);

        assertEq(grt.balanceOf(user), 80 ether);
    }

    function test_BridgeMintingAndBurning_RevertWhen_GatewayMintsAsRegularMinter() public {
        _configureBridge();

        vm.expectRevert(bytes("Only minter can call"));
        vm.prank(mockL2Gateway);
        grt.mint(user, 100 ether);
    }
}
