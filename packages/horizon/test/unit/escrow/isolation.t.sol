// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowIsolationTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testIsolation_DifferentCollectorsSamePayerReceiver(uint256 amount) public useGateway {
        amount = bound(amount, 1, MAX_STAKING_TOKENS / 2);

        address collector1 = users.verifier;
        address collector2 = users.operator;

        _depositTokens(collector1, users.indexer, amount);
        _depositTokens(collector2, users.indexer, amount * 2);

        IPaymentsEscrow.EscrowAccount memory account1 = escrow.getEscrowAccount(
            users.gateway,
            collector1,
            users.indexer
        );
        IPaymentsEscrow.EscrowAccount memory account2 = escrow.getEscrowAccount(
            users.gateway,
            collector2,
            users.indexer
        );

        assertEq(account1.balance, amount);
        assertEq(account2.balance, amount * 2);
    }

    function testIsolation_DifferentReceiversSamePayerCollector(uint256 amount) public useGateway {
        amount = bound(amount, 1, MAX_STAKING_TOKENS / 2);

        address receiver1 = users.indexer;
        address receiver2 = users.delegator;

        _depositTokens(users.verifier, receiver1, amount);
        _depositTokens(users.verifier, receiver2, amount * 2);

        IPaymentsEscrow.EscrowAccount memory account1 = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            receiver1
        );
        IPaymentsEscrow.EscrowAccount memory account2 = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            receiver2
        );

        assertEq(account1.balance, amount);
        assertEq(account2.balance, amount * 2);
    }

    function testIsolation_ThawOneTupleDoesNotAffectAnother(uint256 amount) public useGateway {
        amount = bound(amount, 2, MAX_STAKING_TOKENS / 2);

        _depositTokens(users.verifier, users.indexer, amount);
        _depositTokens(users.verifier, users.delegator, amount);

        // Thaw only the first tuple
        escrow.thaw(users.verifier, users.indexer, amount / 2);

        // Second tuple should be unaffected
        IPaymentsEscrow.EscrowAccount memory account2 = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.delegator
        );
        assertEq(account2.tokensThawing, 0);
        assertEq(account2.thawEndTimestamp, 0);

        // First tuple should have thawing
        IPaymentsEscrow.EscrowAccount memory account1 = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account1.tokensThawing, amount / 2);
    }

    function testIsolation_GetEscrowAccount_NeverUsedAccount() public view {
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            address(0xdead),
            address(0xbeef),
            address(0xface)
        );
        assertEq(account.balance, 0);
        assertEq(account.tokensThawing, 0);
        assertEq(account.thawEndTimestamp, 0);
    }
}
