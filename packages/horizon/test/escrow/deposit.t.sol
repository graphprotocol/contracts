// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowDepositTest is GraphEscrowTest {

    /*
     * TESTS
     */

    function testDeposit_Tokens(uint256 amount) public useGateway useDeposit(amount) {
        (uint256 indexerEscrowBalance,,) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        assertEq(indexerEscrowBalance, amount);
    }
}