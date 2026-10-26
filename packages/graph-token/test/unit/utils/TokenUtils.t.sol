// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IGraphTokenLike } from "../interfaces/IGraphTokenLike.sol";
import { ITokenUtilsMock } from "../interfaces/ITokenUtilsMock.sol";

contract TokenUtilsTest is ProtocolFixture {
    string internal constant GRAPH_TOKEN = string.concat(PKG_ARTIFACTS, "token/GraphToken.sol/GraphToken.json");
    string internal constant TOKEN_UTILS_MOCK =
        string.concat(PKG_ARTIFACTS, "tests/TokenUtilsMock.sol/TokenUtilsMock.json");

    IGraphTokenLike internal grt;
    ITokenUtilsMock internal utils;
    address internal holder = makeAddr("holder");

    function setUp() public {
        vm.warp(1_700_000_000);
        _deployProtocolBase();

        vm.prank(governor);
        grt = IGraphTokenLike(_deployArtifact(GRAPH_TOKEN, abi.encode(10_000_000_000 ether)));
        utils = ITokenUtilsMock(_deployArtifact(TOKEN_UTILS_MOCK, ""));

        vm.prank(governor);
        grt.mint(holder, 1000 ether);
    }

    function test_TokenUtils_PullTokensMovesTokensToCaller() public {
        vm.prank(holder);
        grt.approve(address(utils), 400 ether);

        utils.pullTokens(grt, holder, 400 ether);

        assertEq(grt.balanceOf(holder), 600 ether);
        assertEq(grt.balanceOf(address(utils)), 400 ether);
    }

    function test_TokenUtils_PullTokensZeroDoesNothing() public {
        // No approval: a nonzero pull would revert
        utils.pullTokens(grt, holder, 0);

        assertEq(grt.balanceOf(holder), 1000 ether);
        assertEq(grt.balanceOf(address(utils)), 0);
    }

    function test_TokenUtils_PushTokensMovesTokensFromCaller() public {
        vm.prank(holder);
        grt.transfer(address(utils), 500 ether);

        utils.pushTokens(grt, holder, 300 ether);

        assertEq(grt.balanceOf(holder), 800 ether);
        assertEq(grt.balanceOf(address(utils)), 200 ether);
    }

    function test_TokenUtils_PushTokensZeroDoesNothing() public {
        // Mock holds nothing: a nonzero push would revert
        utils.pushTokens(grt, holder, 0);

        assertEq(grt.balanceOf(holder), 1000 ether);
        assertEq(grt.balanceOf(address(utils)), 0);
    }

    function test_TokenUtils_BurnTokensLowersTotalSupply() public {
        vm.prank(holder);
        grt.transfer(address(utils), 500 ether);
        uint256 supplyBefore = grt.totalSupply();

        utils.burnTokens(grt, 200 ether);

        assertEq(grt.totalSupply(), supplyBefore - 200 ether);
        assertEq(grt.balanceOf(address(utils)), 300 ether);
    }
}
