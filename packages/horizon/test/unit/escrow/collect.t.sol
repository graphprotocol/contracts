// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectTest is GraphEscrowTest {
    /*
     * TESTS
     */

    // use users.verifier as collector
    function testCollect_Tokens(
        uint256 tokens,
        uint256 tokensToCollect,
        uint256 delegationTokens,
        uint256 dataServiceCut
    )
        public
        useIndexer
        useProvision(tokens, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, DELEGATION_FEE_CUT)
    {
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        delegationTokens = bound(delegationTokens, MIN_DELEGATION, MAX_STAKING_TOKENS);
        tokensToCollect = bound(tokensToCollect, 1, MAX_STAKING_TOKENS);

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokensToCollect);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            tokensToCollect,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
    }

    function testCollect_Tokens_NoProvision(
        uint256 tokens,
        uint256 dataServiceCut
    ) public useIndexer useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, DELEGATION_FEE_CUT) {
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokens);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            tokens,
            subgraphDataServiceAddress,
            dataServiceCut,
            users.indexer
        );
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow(
        uint256 amount,
        uint256 insufficientAmount
    ) public useGateway useDeposit(insufficientAmount) {
        vm.assume(amount > 0);
        vm.assume(insufficientAmount < amount);

        vm.startPrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature(
            "PaymentsEscrowInsufficientBalance(uint256,uint256)",
            insufficientAmount,
            amount
        );
        vm.expectRevert(expectedError);
        escrow.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );
        vm.stopPrank();
    }

    function testCollect_MultipleCollections(
        uint256 depositAmount,
        uint256 firstCollect,
        uint256 secondCollect
    ) public useIndexer {
        // Tests multiple collect operations from the same escrow account
        vm.assume(firstCollect < MAX_STAKING_TOKENS);
        vm.assume(secondCollect < MAX_STAKING_TOKENS);
        vm.assume(depositAmount > 0);
        vm.assume(firstCollect > 0 && firstCollect < depositAmount);
        vm.assume(secondCollect > 0 && secondCollect <= depositAmount - firstCollect);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, depositAmount);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            firstCollect,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );
    }

    function testCollect_EntireBalance(uint256 tokens) public useIndexer {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokens);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            tokens,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );

        // Balance should be zero
        (uint256 balance, , ) = escrow.escrowAccounts(users.gateway, users.verifier, users.indexer);
        assertEq(balance, 0);
    }

    function testCollect_CapsTokensThawingToZero_ResetsThawEndTimestamp(uint256 tokens) public useIndexer {
        // When collecting the entire balance while thawing, tokensThawing should cap to 0
        // and thawEndTimestamp should reset to 0
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokens);
        escrow.thaw(users.verifier, users.indexer, tokens);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        // Collect entire balance
        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            tokens,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );

        // tokensThawing and thawEndTimestamp should be reset
        (uint256 balance, uint256 tokensThawingResult, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(balance, 0);
        assertEq(tokensThawingResult, 0, "tokensThawing should be capped to 0");
        assertEq(thawEndTimestamp, 0, "thawEndTimestamp should reset when tokensThawing is 0");
    }

    function testCollect_CapsTokensThawingBelowBalance(uint256 depositAmount, uint256 collectAmount) public useIndexer {
        // When collecting reduces balance below tokensThawing, tokensThawing should cap at balance
        depositAmount = bound(depositAmount, 3, MAX_STAKING_TOKENS);
        collectAmount = bound(collectAmount, 1, depositAmount - 1);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, depositAmount);
        // Thaw entire balance
        escrow.thaw(users.verifier, users.indexer, depositAmount);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        // Collect partial amount
        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            collectAmount,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );

        (uint256 balance, uint256 tokensThawingResult, ) = escrow.escrowAccounts(
            users.gateway,
            users.verifier,
            users.indexer
        );
        uint256 remainingBalance = depositAmount - collectAmount;
        assertEq(balance, remainingBalance);
        assertEq(tokensThawingResult, remainingBalance, "tokensThawing should cap at remaining balance");
    }

    function testCollect_RevertWhen_InconsistentCollection(uint256 tokens) public useGateway {
        tokens = bound(tokens, 1, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, tokens);

        // Mock GraphPayments.collect to be a no-op: it succeeds but doesn't pull tokens,
        // causing the escrow balance to remain unchanged and triggering the consistency check.
        vm.mockCall(address(payments), abi.encodeWithSelector(IGraphPayments.collect.selector), abi.encode());

        uint256 escrowBalance = token.balanceOf(address(escrow));

        resetPrank(users.verifier);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPaymentsEscrow.PaymentsEscrowInconsistentCollection.selector,
                escrowBalance,
                escrowBalance, // balance unchanged because mock didn't pull tokens
                tokens
            )
        );
        escrow.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            tokens,
            subgraphDataServiceAddress,
            0,
            users.indexer
        );

        vm.clearMockedCalls();
    }
}
