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

        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokens);

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

    function testCollect_RevertWhen_InvalidPool(
        uint256 amount
    )
        public
        useIndexer
        useProvision(amount, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut)
    {
        vm.assume(amount > 1 ether);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, amount);

        resetPrank(users.verifier);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        escrow.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            1
        );
    }

    function testCollect_RevertWhen_InvalidProvision(
        uint256 amount
    ) public useIndexer useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(amount > 1 ether);
        vm.assume(amount <= MAX_STAKING_TOKENS);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, amount);

        resetPrank(users.verifier);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidProvision.selector,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        escrow.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            1
        );
    }
}
