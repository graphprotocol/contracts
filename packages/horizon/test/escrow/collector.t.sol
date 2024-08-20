// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectorTest is GraphEscrowTest {

    function _approveCollector(uint256 tokens) internal {
        escrow.approveCollector(users.verifier, tokens);

        (bool authorized, uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertTrue(authorized);
        assertEq(allowance, tokens);
        assertEq(thawEndTimestamp, 0);
    }

    function _thawCollector() internal {
        escrow.thawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertTrue(authorized);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    function _cancelThawCollector() internal {
        escrow.cancelThawCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertTrue(authorized);
        assertEq(thawEndTimestamp, 0);
    }

    function _revokeCollector() internal {
        escrow.revokeCollector(users.verifier);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertFalse(authorized);
        assertEq(thawEndTimestamp, 0);
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