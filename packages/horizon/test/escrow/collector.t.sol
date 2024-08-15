// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectorTest is GraphEscrowTest {

    function _approveCollector(uint256 tokens) internal {
        escrow.approveCollector(users.verifier, tokens);

        bool authorized = escrow.isCollectorAuthorized(users.gateway, users.verifier);
        bool isThawing = escrow.isCollectorThawing(users.gateway, users.verifier);
        uint256 thawEndTimeRemaining = escrow.getCollectorThawTimeRemaining(users.gateway, users.verifier);
        assertTrue(authorized);
        assertFalse(isThawing);
        assertEq(thawEndTimeRemaining, 0);
    }

    function _thawCollector() internal {
        escrow.thawCollector(users.verifier);

        bool authorized = escrow.isCollectorAuthorized(users.gateway, users.verifier);
        bool isThawing = escrow.isCollectorThawing(users.gateway, users.verifier);
        uint256 thawEndTimeRemaining = escrow.getCollectorThawTimeRemaining(users.gateway, users.verifier);
        assertTrue(authorized);
        assertTrue(isThawing);
        assertEq(thawEndTimeRemaining, revokeCollectorThawingPeriod);
    }

    function _cancelThawCollector() internal {
        escrow.cancelThawCollector(users.verifier);

        bool authorized = escrow.isCollectorAuthorized(users.gateway, users.verifier);
        bool isThawing = escrow.isCollectorThawing(users.gateway, users.verifier);
        uint256 thawEndTimeRemaining = escrow.getCollectorThawTimeRemaining(users.gateway, users.verifier);
        assertTrue(authorized);
        assertFalse(isThawing);
        assertEq(thawEndTimeRemaining, 0);
    }

    function _revokeCollector() internal {
        escrow.revokeCollector(users.verifier);

        bool authorized = escrow.isCollectorAuthorized(users.gateway, users.verifier);
        bool isThawing = escrow.isCollectorThawing(users.gateway, users.verifier);
        uint256 thawEndTimeRemaining = escrow.getCollectorThawTimeRemaining(users.gateway, users.verifier);
        assertFalse(authorized);
        assertFalse(isThawing);
        assertEq(thawEndTimeRemaining, 0);
    }

    /*
     * TESTS
     */

    function testCollector_Approve(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
    }

    function testCollector_RevertWhen_ApprovingForSmallerAllowance(
        uint256 tokens,
        uint256 lessTokens
    ) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        vm.assume(lessTokens < tokens);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowInconsistentAllowance(uint256,uint256)", tokens, lessTokens);
        vm.expectRevert(expectedError);
        escrow.approveCollector(users.verifier, lessTokens);
    }

    function testCollector_Thaw(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        _thawCollector();
    }

    function testCollector_CancelThaw(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        _thawCollector();
        _cancelThawCollector();
    }

    function testCollector_RevertWhen_CancelThawIsNotThawing(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(users.verifier);
        vm.stopPrank();
    }

    function testCollector_Revoke(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        _thawCollector();
        skip(revokeCollectorThawingPeriod + 1);
        _revokeCollector();
    }

    function testCollector_RevertWhen_RevokeIsNotThawing(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }

    function testCollector_RevertWhen_RevokeIsStillThawing(uint256 tokens) public useGateway {
        vm.assume(tokens > 0);
        _approveCollector(tokens);
        escrow.thawCollector(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }
}