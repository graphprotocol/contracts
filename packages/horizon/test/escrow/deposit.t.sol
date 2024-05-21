// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowDepositTest is GraphEscrowTest {

    function testDeposit_Tokens(uint256 amount) public useGateway depositTokens(amount) {
        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.indexer);
        assertEq(indexerEscrowBalance, amount);
    }
}