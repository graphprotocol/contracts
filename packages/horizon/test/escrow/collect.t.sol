// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testCollect_Tokens(
        uint256 tokens,
        uint256 tokensToCollect,
        uint256 delegationTokens,
        uint256 dataServiceCut
    )
        public
        useIndexer
        useProvision(tokens, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut)
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
            dataServiceCut
        );
    }

    function testCollect_Tokens_NoProvision(
        uint256 tokens,
        uint256 dataServiceCut
    ) public useIndexer useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
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
            dataServiceCut
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
            0
        );
        vm.stopPrank();
    }
}
