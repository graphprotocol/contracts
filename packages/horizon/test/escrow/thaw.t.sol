// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowThawTest is GraphEscrowTest {

    function testThaw_Tokens(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.indexer, amount);

        (, uint256 amountThawing,uint256 thawEndTimestamp) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(amountThawing, amount);
        assertEq(thawEndTimestamp, block.timestamp + withdrawEscrowThawingPeriod);
    }

    function testThaw_RevertWhen_InsufficientThawAmount(
        uint256 amount
    ) public useGateway useDeposit(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.thaw(users.indexer, 0);
    }

    function testThaw_RevertWhen_InsufficientAmount(
        uint256 amount,
        uint256 overAmount
    ) public useGateway useDeposit(amount) {
        overAmount = bound(overAmount, amount + 1, type(uint256).max);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowInsufficientBalance(uint256,uint256)", amount, overAmount);
        vm.expectRevert(expectedError);
        escrow.thaw(users.indexer, overAmount);
    }

    function testThaw_CancelRequest(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.indexer, amount);
        escrow.thaw(users.indexer, 0);

        (, uint256 amountThawing,uint256 thawEndTimestamp) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(amountThawing, 0);
        assertEq(thawEndTimestamp, 0);
    }
}