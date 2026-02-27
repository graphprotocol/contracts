// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowGettersTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testGetEscrowAccount(uint256 amount) public useGateway useDeposit(amount) {
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.balance, amount);
        assertEq(account.tokensThawing, 0);
    }

    function testGetEscrowAccount_WhenThawing(
        uint256 amountDeposit,
        uint256 amountThawing
    ) public useGateway useDeposit(amountDeposit) {
        vm.assume(amountThawing > 0);
        vm.assume(amountDeposit >= amountThawing);

        // thaw some funds
        _thawEscrow(users.verifier, users.indexer, amountThawing);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.balance - account.tokensThawing, amountDeposit - amountThawing);
    }

    function testGetEscrowAccount_WhenCollectedOverThawing(
        uint256 amountDeposit,
        uint256 amountThawing,
        uint256 amountCollected
    ) public useGateway {
        // Limit thawing and collected to half of MAX_STAKING_TOKENS to ensure valid deposit range
        amountThawing = bound(amountThawing, 1, MAX_STAKING_TOKENS / 2);
        amountCollected = bound(amountCollected, 1, MAX_STAKING_TOKENS / 2);

        // amountDeposit must be:
        // - >= amountThawing (so we can thaw that amount)
        // - >= amountCollected (so we can collect that amount)
        // - < amountThawing + amountCollected (so that after collecting, balance < thawing)
        // With the above bounds, this range is guaranteed to be valid
        uint256 minDeposit = amountThawing > amountCollected ? amountThawing : amountCollected;
        uint256 maxDeposit = amountThawing + amountCollected - 1;
        amountDeposit = bound(amountDeposit, minDeposit, maxDeposit);

        _depositTokens(users.verifier, users.indexer, amountDeposit);

        // thaw some funds
        _thawEscrow(users.verifier, users.indexer, amountThawing);

        // users start with max uint256 balance so we burn to avoid overflow
        // TODO: we should modify all tests to consider users have a max balance thats less than max uint256
        resetPrank(users.indexer);
        token.burn(amountCollected);

        // collect some funds to get the balance of the account below the amount thawing
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

        // tokensThawing > balance after collection, so effective available is 0
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.balance, amountDeposit - amountCollected);
        assertTrue(account.tokensThawing >= account.balance);
    }
}
