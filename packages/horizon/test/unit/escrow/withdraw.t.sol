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

    function testWithdraw_RevertWhen_NotThawing(uint256 amount) public useGateway useDeposit(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.withdraw(users.verifier, users.indexer);
    }

    function testWithdraw_RevertWhen_StillThawing(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        bytes memory expectedError = abi.encodeWithSignature(
            "PaymentsEscrowStillThawing(uint256,uint256)",
            block.timestamp,
            block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD
        );
        vm.expectRevert(expectedError);
        escrow.withdraw(users.verifier, users.indexer);
    }

    function testWithdraw_RevertWhen_AtExactThawEndTimestamp(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // Advance time to exactly the thaw end timestamp (boundary: thawEndTimestamp < block.timestamp required)
        skip(WITHDRAW_ESCROW_THAWING_PERIOD);

        (, , uint256 thawEndTimestamp) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        bytes memory expectedError = abi.encodeWithSignature(
            "PaymentsEscrowStillThawing(uint256,uint256)",
            block.timestamp,
            thawEndTimestamp
        );
        vm.expectRevert(expectedError);
        escrow.withdraw(users.verifier, users.indexer);
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
        // Withdraw succeeds if tokens remain, otherwise reverts.
        resetPrank(users.gateway);
        (, uint256 tokensThawing, ) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        if (tokensThawing != 0) {
            _withdrawEscrow(users.verifier, users.indexer);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowNotThawing.selector));
            escrow.withdraw(users.verifier, users.indexer);
        }
    }
}
