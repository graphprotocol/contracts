// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IPaymentsEscrow } from "../../contracts/interfaces/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectorTest is GraphEscrowTest {

    /*
     * HELPERS
     */

    function _approveCollector(uint256 tokens) internal {
        (uint256 beforeAllowance,) = escrow.authorizedCollectors(users.gateway, users.verifier);
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.AuthorizedCollector(users.gateway, users.verifier);
        escrow.approveCollector(users.verifier, tokens);
        (uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(allowance - beforeAllowance, tokens);
        assertEq(thawEndTimestamp, 0);
    }

    function _thawCollector() internal {
        (uint256 beforeAllowance,) = escrow.authorizedCollectors(users.gateway, users.verifier);
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.ThawCollector(users.gateway, users.verifier);
        escrow.thawCollector(users.verifier);

        (uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(allowance, beforeAllowance);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    function _cancelThawCollector() internal {
        (uint256 beforeAllowance, uint256 beforeThawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertTrue(beforeThawEndTimestamp != 0, "Collector should be thawing");
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.CancelThawCollector(users.gateway, users.verifier);
        escrow.cancelThawCollector(users.verifier);

        (uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(allowance, beforeAllowance);
        assertEq(thawEndTimestamp, 0);
    }

    function _revokeCollector() internal {
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.RevokeCollector(users.gateway, users.verifier);
        escrow.revokeCollector(users.verifier);

        (uint256 allowance, uint256 thawEndTimestamp) = escrow.authorizedCollectors(users.gateway, users.verifier);
        assertEq(allowance, 0);
        assertEq(thawEndTimestamp, 0);
    }

    /*
     * TESTS
     */

    function testCollector_Approve(
        uint256 tokens,
        uint256 approveSteps
    ) public useGateway {
        approveSteps = bound(approveSteps, 1, 100);
        vm.assume(tokens > approveSteps);

        uint256 approveTokens = tokens / approveSteps;
        for (uint i = 0; i < approveSteps; i++) {
            _approveCollector(approveTokens);
        }
    }

    function testCollector_RevertWhen_ApprovingForZeroAllowance(
        uint256 amount
    ) public useGateway useCollector(amount) {
        bytes memory expectedError = abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowInvalidZeroTokens.selector);
        vm.expectRevert(expectedError);
        escrow.approveCollector(users.verifier, 0);
    }

    function testCollector_Thaw(uint256 amount) public useGateway useCollector(amount) {
        _thawCollector();
    }

    function testCollector_CancelThaw(uint256 amount) public useGateway useCollector(amount) {
        _thawCollector();
        _cancelThawCollector();
    }

    function testCollector_RevertWhen_CancelThawIsNotThawing(uint256 amount) public useGateway useCollector(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(users.verifier);
        vm.stopPrank();
    }

    function testCollector_Revoke(uint256 amount) public useGateway useCollector(amount) {
        _thawCollector();
        skip(revokeCollectorThawingPeriod + 1);
        _revokeCollector();
    }

    function testCollector_RevertWhen_RevokeIsNotThawing(uint256 amount) public useGateway useCollector(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }

    function testCollector_RevertWhen_RevokeIsStillThawing(uint256 amount) public useGateway useCollector(amount) {
        escrow.thawCollector(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(users.verifier);
    }
}