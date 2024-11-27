// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../../contracts/interfaces/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowCollectTest is GraphEscrowTest {

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
    }

    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _tokensDataService
    ) private {
        (, address _collector, ) = vm.readCallers();

        // Previous balances
        (uint256 previousPayerEscrowBalance,,) = escrow.escrowAccounts(_payer, _collector, _receiver);
        CollectPaymentData memory previousBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(
                _receiver,
                _dataService
            ),
            dataServiceBalance: token.balanceOf(_dataService)
        });

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.EscrowCollected(_payer, _collector, _receiver, _tokens);
        escrow.collect(_paymentType, _payer, _receiver, _tokens, _dataService, _tokensDataService);

        // Calculate cuts
        uint256 protocolPaymentCut = payments.PROTOCOL_PAYMENT_CUT();
        uint256 delegatorCut = staking.getDelegationFeeCut(
            _receiver,
            _dataService,
            _paymentType
        );

        // After balances
        (uint256 afterPayerEscrowBalance,,) = escrow.escrowAccounts(_payer, _collector, _receiver);
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(
                _receiver,
                _dataService
            ),
            dataServiceBalance: token.balanceOf(_dataService)
        });

        // Check receiver balance after payment
        uint256 receiverExpectedPayment = _tokens - _tokensDataService - _tokens * protocolPaymentCut / MAX_PPM - _tokens * delegatorCut / MAX_PPM;
        assertEq(afterBalances.receiverBalance - previousBalances.receiverBalance, receiverExpectedPayment);
        assertEq(token.balanceOf(address(payments)), 0);

        // Check delegation pool balance after payment
        assertEq(afterBalances.delegationPoolBalance - previousBalances.delegationPoolBalance, _tokens * delegatorCut / MAX_PPM);

        // Check that the escrow account has been updated
        assertEq(previousBalances.escrowBalance, afterBalances.escrowBalance + _tokens);

        // Check that payments balance didn't change
        assertEq(previousBalances.paymentsBalance, afterBalances.paymentsBalance);

        // Check data service balance after payment
        assertEq(afterBalances.dataServiceBalance - previousBalances.dataServiceBalance, _tokensDataService);

        // Check payers escrow balance after payment
        assertEq(previousPayerEscrowBalance - _tokens, afterPayerEscrowBalance);
    }

    /*
     * TESTS
     */

    function testCollect_Tokens(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 tokensDataService
    ) public useIndexer useProvision(tokens, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        uint256 tokensProtocol = tokens * protocolPaymentCut / MAX_PPM;
        uint256 tokensDelegatoion = tokens * delegationFeeCut / MAX_PPM;
        vm.assume(tokensDataService < tokens - tokensProtocol - tokensDelegatoion);

        delegationTokens = bound(delegationTokens, 1, MAX_STAKING_TOKENS);
        resetPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, delegationTokens, 0);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, tokens);

        resetPrank(users.verifier);
        _collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, tokens, subgraphDataServiceAddress, tokensDataService);
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow(
        uint256 amount, 
        uint256 insufficientAmount
    ) public useGateway useDeposit(insufficientAmount)  {
        vm.assume(amount > 0);
        vm.assume(insufficientAmount < amount);

        vm.startPrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowInsufficientBalance(uint256,uint256)", insufficientAmount, amount);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, 0);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_InvalidPool(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(amount > 1 ether);

        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, amount);

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, 1);
    }

    function testCollect_RevertWhen_InvalidProvision(
        uint256 amount
    ) public useIndexer useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(amount > 1 ether);
        vm.assume(amount <= MAX_STAKING_TOKENS);
        
        resetPrank(users.gateway);
        _depositTokens(users.verifier, users.indexer, amount);

        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidProvision.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, 1);
    }
}