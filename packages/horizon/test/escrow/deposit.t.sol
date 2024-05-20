// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowDepositTest is GraphEscrowTest {

    function testDeposit_Tokens(uint256 amount) public useGateway depositTokens(amount) {
        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, amount);
    }

    function testDeposit_ManyDeposits(uint256 amount) public useGateway approveEscrow(amount) {
        uint256 amountOne = amount / 2;
        uint256 amountTwo = amount - amountOne;

        address otherIndexer = address(0xB3);
        address[] memory indexers = new address[](2);
        indexers[0] = users.indexer;
        indexers[1] = otherIndexer;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountOne;
        amounts[1] = amountTwo;

        escrow.depositMany(indexers, amounts);

        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, amountOne);

        (uint256 otherIndexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, otherIndexer);
        assertEq(otherIndexerEscrowBalance, amountTwo);
    }

    function testDeposit_RevertWhen_ManyDepositsInputsLengthMismatch(
        uint256 amount
    ) public useGateway approveEscrow(amount) {
        address otherIndexer = address(0xB3);
        address[] memory indexers = new address[](2);
        indexers[0] = users.indexer;
        indexers[1] = otherIndexer;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInputsLengthMismatch()");
        vm.expectRevert(expectedError);
        escrow.depositMany(indexers, amounts);
    }
}