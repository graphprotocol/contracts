// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowWithdrawTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testWithdraw_Tokens(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // advance time
        skip(WITHDRAW_ESCROW_THAWING_PERIOD + 1);

        _withdrawEscrow(users.verifier, users.indexer);
        vm.stopPrank();
    }

    function testWithdraw_NoopWhenNotThawing(uint256 amount) public useGateway useDeposit(amount) {
        uint256 tokens = escrow.withdraw(users.verifier, users.indexer);
        assertEq(tokens, 0);
    }

    function testWithdraw_NoopWhenStillThawing(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        uint256 tokens = escrow.withdraw(users.verifier, users.indexer);
        assertEq(tokens, 0);

        // Account unchanged
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, thawAmount);
    }

    function testWithdraw_NoopAtExactThawEndTimestamp(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // Advance time to exactly the thaw end timestamp (boundary: block.timestamp <= thawEnd)
        skip(WITHDRAW_ESCROW_THAWING_PERIOD);

        uint256 tokens = escrow.withdraw(users.verifier, users.indexer);
        assertEq(tokens, 0, "Should not withdraw when timestamp equals thawEnd");

        // Account unchanged
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, thawAmount);
    }

    function testWithdraw_SucceedsOneSecondAfterThawEnd(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // Advance time to exactly one second past thaw end
        skip(WITHDRAW_ESCROW_THAWING_PERIOD + 1);

        _withdrawEscrow(users.verifier, users.indexer);
    }

    function testWithdraw_BalanceAfterCollect(
        uint256 amountDeposited,
        uint256 amountThawed,
        uint256 amountCollected
    ) public useGateway depositAndThawTokens(amountDeposited, amountThawed) {
        vm.assume(amountCollected > 0);
        vm.assume(amountCollected <= amountDeposited);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        // collect
        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amountCollected,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );

        // Advance time to simulate the thawing period
        skip(WITHDRAW_ESCROW_THAWING_PERIOD + 1);

        // After collect, tokensThawing is capped at remaining balance.
        // Withdraw succeeds if tokens remain, otherwise is a no-op.
        resetPrank(users.gateway);
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        if (account.tokensThawing != 0) {
            _withdrawEscrow(users.verifier, users.indexer);
        } else {
            uint256 tokens = escrow.withdraw(users.verifier, users.indexer);
            assertEq(tokens, 0);
        }
    }
}
