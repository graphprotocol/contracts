// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowWithdrawTest is GraphEscrowTest {

    modifier depositAndThawTokens(uint256 amount, uint256 thawAmount) {
        vm.assume(thawAmount > 0);  
        vm.assume(amount > thawAmount);
        _depositTokens(amount);
        escrow.thaw(users.indexer, thawAmount);
        _;
    }

    function testWithdraw_Tokens(
        uint256 amount, 
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // advance time
        skip(withdrawEscrowThawingPeriod + 1);

        escrow.withdraw(users.indexer);
        vm.stopPrank();

        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, amount - thawAmount);
    }

    function testWithdraw_RevertWhen_NotThawing(uint256 amount) public useGateway useDeposit(amount) {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.withdraw(users.indexer);
        vm.stopPrank();
    }

    function testWithdraw_RevertWhen_StillThawing(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + withdrawEscrowThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.withdraw(users.indexer);
        vm.stopPrank();
    }
}