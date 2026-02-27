// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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

        (uint256 balance1, , ) = escrow.escrowAccounts(users.gateway, collector1, users.indexer);
        (uint256 balance2, , ) = escrow.escrowAccounts(users.gateway, collector2, users.indexer);

        assertEq(balance1, amount);
        assertEq(balance2, amount * 2);
    }

    function testIsolation_DifferentReceiversSamePayerCollector(uint256 amount) public useGateway {
        amount = bound(amount, 1, MAX_STAKING_TOKENS / 2);

        address receiver1 = users.indexer;
        address receiver2 = users.delegator;

        _depositTokens(users.verifier, receiver1, amount);
        _depositTokens(users.verifier, receiver2, amount * 2);

        (uint256 balance1, , ) = escrow.escrowAccounts(users.gateway, users.verifier, receiver1);
        (uint256 balance2, , ) = escrow.escrowAccounts(users.gateway, users.verifier, receiver2);

        assertEq(balance1, amount);
        assertEq(balance2, amount * 2);
    }

    function testIsolation_ThawOneTupleDoesNotAffectAnother(uint256 amount) public useGateway {
        amount = bound(amount, 2, MAX_STAKING_TOKENS / 2);

        _depositTokens(users.verifier, users.indexer, amount);
        _depositTokens(users.verifier, users.delegator, amount);

        // Thaw only the first tuple
        escrow.thaw(users.verifier, users.indexer, amount / 2);

        // Second tuple should be unaffected
        (, uint256 tokensThawing2, uint256 thawEndTimestamp2) = escrow.escrowAccounts(
            users.gateway,
            users.verifier,
            users.delegator
        );
        assertEq(tokensThawing2, 0);
        assertEq(thawEndTimestamp2, 0);

        // First tuple should have thawing
        (, uint256 tokensThawing1, ) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        assertEq(tokensThawing1, amount / 2);
    }

    function testIsolation_EscrowAccounts_NeverUsedAccount() public view {
        (uint256 balance, uint256 tokensThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            address(0xdead),
            address(0xbeef),
            address(0xface)
        );
        assertEq(balance, 0);
        assertEq(tokensThawing, 0);
        assertEq(thawEndTimestamp, 0);
    }
}
