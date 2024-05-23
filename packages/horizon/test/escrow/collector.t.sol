// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectorTest is GraphEscrowTest {

    // Collector approve tests

    function testCollector_Approve(uint256 amount) public useGateway useCollector(amount) {
        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCollector_RevertWhen_ApprovingForSmallerAllowance(
        uint256 amount,
        uint256 smallerAmount
    ) public useGateway useCollector(amount) {
        vm.assume(smallerAmount < amount);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAllowance(uint256,uint256)", amount, smallerAmount);
        vm.expectRevert(expectedError);
        escrow.approveCollector(users.verifier, smallerAmount);
    }

    // Collector thaw tests

    function testCollector_Thaw(uint256 amount) public useGateway useCollector(amount) {
        escrow.thawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    // Collector cancel thaw tests

    function testCollector_CancelThaw(uint256 amount) public useGateway useCollector(amount) {
        escrow.thawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        escrow.cancelThawCollector(users.verifier);

        (authorized,, thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCollector_RevertWhen_CancelThawIsNotThawing(uint256 amount) public useGateway useCollector(amount) {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(users.verifier);
        vm.stopPrank();
    }

    // Collector revoke tests

    function testCollector_Revoke(uint256 amount) public useGateway useCollector(amount) {
        escrow.thawCollector(users.verifier);
        skip(revokeCollectorThawingPeriod + 1);
        escrow.revokeCollector(users.verifier);

        (bool authorized,,) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(authorized, false);
    }

    function testCollector_RevertWhen_RevokeIsNotThawing(uint256 amount) public useGateway useCollector(amount) {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }

    function testCollector_RevertWhen_RevokeIsStillThawing(uint256 amount) public useGateway useCollector(amount) {
        escrow.thawCollector(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }
}