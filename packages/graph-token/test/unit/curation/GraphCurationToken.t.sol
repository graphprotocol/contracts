// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";
import { IGraphCurationTokenLike } from "../interfaces/IGraphCurationTokenLike.sol";

contract GraphCurationTokenTest is ProtocolFixture {
    IGraphCurationTokenLike internal gcs;
    address internal user = makeAddr("user");

    function setUp() public {
        governor = makeAddr("governor");
        gcs = IGraphCurationTokenLike(_deployPkg("GraphCurationToken.sol:GraphCurationToken", ""));
        gcs.initialize(governor);
    }

    function test_Initialize_SetsGovernorAndMetadata() public view {
        assertEq(gcs.governor(), governor);
        assertEq(gcs.name(), "Graph Curation Share");
        assertEq(gcs.symbol(), "GCS");
    }

    function test_Mint_RevertWhen_NotGovernor() public {
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(user);
        gcs.mint(user, 1 ether);
    }

    function test_Mint_MintsTokens() public {
        vm.prank(governor);
        gcs.mint(user, 1 ether);
        assertEq(gcs.balanceOf(user), 1 ether);
        assertEq(gcs.totalSupply(), 1 ether);
    }

    function test_BurnFrom_RevertWhen_NotGovernor() public {
        vm.prank(governor);
        gcs.mint(user, 1 ether);
        vm.expectRevert(bytes("Only Governor can call"));
        vm.prank(user);
        gcs.burnFrom(user, 1 ether);
    }

    function test_BurnFrom_BurnsWithoutAllowance() public {
        vm.startPrank(governor);
        gcs.mint(user, 1 ether);
        gcs.burnFrom(user, 0.4 ether);
        vm.stopPrank();
        assertEq(gcs.balanceOf(user), 0.6 ether);
        assertEq(gcs.totalSupply(), 0.6 ether);
    }
}
