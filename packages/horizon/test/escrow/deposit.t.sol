// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowDepositTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testDeposit_Tokens(uint256 amount) public useGateway useDeposit(amount) {
        (uint256 indexerEscrowBalance, , ) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        assertEq(indexerEscrowBalance, amount);
    }

    function testDepositTo_Tokens(uint256 amount) public {
        resetPrank(users.delegator);
        token.approve(address(escrow), amount);
        _depositToTokens(users.gateway, users.verifier, users.indexer, amount);
    }

    // Tests multiple deposits accumulate correctly in the escrow account
    function testDeposit_MultipleDeposits(uint256 amount1, uint256 amount2) public useGateway {
        vm.assume(amount1 > 0);
        vm.assume(amount2 > 0);
        vm.assume(amount1 <= MAX_STAKING_TOKENS);
        vm.assume(amount2 <= MAX_STAKING_TOKENS);

        _depositTokens(users.verifier, users.indexer, amount1);
        _depositTokens(users.verifier, users.indexer, amount2);

        (uint256 balance,,) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        assertEq(balance, amount1 + amount2);
    }
}
