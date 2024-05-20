// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectorTest is GraphEscrowTest {
    function setUp() public virtual override {
        GraphEscrowTest.setUp();
        vm.prank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
    }

    // Collector approve tests

    function testCollector_Approve() public view {
        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    // Collector thaw tests

    function testCollector_Thaw() public {
        vm.prank(users.gateway);
        escrow.thawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    // Collector cancel thaw tests

    function testCollector_CancelThaw() public {
        vm.prank(users.gateway);
        escrow.thawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        vm.prank(users.gateway);
        escrow.cancelThawCollector(users.verifier);

        (authorized,, thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCollector_RevertWhen_CancelThawIsNotThawing() public {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(users.verifier);
        vm.stopPrank();
    }

    // Collector revoke tests

    function testCollector_Revoke() public {
        vm.startPrank(users.gateway);
        escrow.thawCollector(users.verifier);
        skip(revokeCollectorThawingPeriod + 1);
        escrow.revokeCollector(users.verifier);
        vm.stopPrank();

        (bool authorized,,) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, false);
    }

    function testCollector_RevertWhen_RevokeIsNotThawing() public {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        vm.prank(users.gateway);
        escrow.revokeCollector(users.verifier);
    }

    function testCollector_RevertWhen_RevokeIsStillThawing() public {
        vm.startPrank(users.gateway);
        escrow.thawCollector(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
        vm.stopPrank();
    }
}