// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { GraphPayments } from "../../contracts/payments/GraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract GraphPaymentsTest is HorizonStakingSharedTest {

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
    }

    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _tokensDataService
    ) private {
        // Previous balances
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

        // Calculate cuts
        uint256 protocolPaymentCut = payments.PROTOCOL_PAYMENT_CUT();
        uint256 delegatorCut = staking.getDelegationFeeCut(
            _receiver,
            _dataService,
            _paymentType
        );
        uint256 tokensProtocol = _tokens * protocolPaymentCut / MAX_PPM;
        uint256 tokensDelegation = _tokens * delegatorCut / MAX_PPM;

        uint256 receiverExpectedPayment = _tokens - _tokensDataService - tokensProtocol - tokensDelegation;

        (,address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(payments));
        emit IGraphPayments.PaymentCollected(
            msgSender,
            _receiver,
            _dataService,
            receiverExpectedPayment,
            tokensDelegation,
            _tokensDataService,
            tokensProtocol
        );
        payments.collect(_paymentType, _receiver, _tokens, _dataService, _tokensDataService);

        // After balances
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
        assertEq(afterBalances.receiverBalance - previousBalances.receiverBalance, receiverExpectedPayment);
        assertEq(token.balanceOf(address(payments)), 0);

        // Check delegation pool balance after payment
        assertEq(afterBalances.delegationPoolBalance - previousBalances.delegationPoolBalance, tokensDelegation);

        // Check that the escrow account has been updated
        assertEq(previousBalances.escrowBalance, afterBalances.escrowBalance + _tokens);

        // Check that payments balance didn't change
        assertEq(previousBalances.paymentsBalance, afterBalances.paymentsBalance);

        // Check data service balance after payment
        assertEq(afterBalances.dataServiceBalance - previousBalances.dataServiceBalance, _tokensDataService);
    }

    /*
     * TESTS
     */

    function testConstructor_RevertIf_InvalidProtocolPaymentCut(uint256 protocolPaymentCut) public {
        protocolPaymentCut = bound(protocolPaymentCut, MAX_PPM + 1, MAX_PPM + 100);

        resetPrank(users.deployer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphPayments.GraphPaymentsInvalidProtocolPaymentCut.selector,
            protocolPaymentCut
        );
        vm.expectRevert(expectedError);
        new GraphPayments(address(controller), protocolPaymentCut);
    }

    function testCollect(
        uint256 amount,
        uint256 tokensDataService,
        uint256 tokensDelegate
    ) public useIndexer useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        uint256 tokensProtocol = amount * protocolPaymentCut / MAX_PPM;
        uint256 tokensDelegation = amount * delegationFeeCut / MAX_PPM;
        vm.assume(tokensDataService < amount - tokensProtocol - tokensDelegation);
        address escrowAddress = address(escrow);

        // Delegate tokens
        vm.assume(tokensDelegate > MIN_DELEGATION);
        vm.assume(tokensDelegate <= MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, tokensDelegate, 0);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, tokensDataService);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_InsufficientAmount(
        uint256 amount,
        uint256 tokensDataService
    ) public useIndexer useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        tokensDataService = bound(tokensDataService, amount + 1, MAX_STAKING_TOKENS + 1);

        address escrowAddress = address(escrow);
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        bytes memory expectedError;
        {
            uint256 tokensProtocol = amount * protocolPaymentCut / MAX_PPM;
            uint256 tokensDelegatoion = amount * delegationFeeCut / MAX_PPM;
            uint256 requiredAmount = tokensDataService + tokensProtocol + tokensDelegatoion;
            expectedError = abi.encodeWithSignature("GraphPaymentsInsufficientTokens(uint256,uint256)", amount, requiredAmount);
        }
        vm.expectRevert(expectedError);
        payments.collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, tokensDataService);
    }

    function testCollect_RevertWhen_InvalidPool(
        uint256 amount
    ) public useIndexer useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(amount > 1 ether);
        address escrowAddress = address(escrow);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        payments.collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, 1);
    }

    function testCollect_RevertWhen_InvalidProvision(
        uint256 amount
    ) public useIndexer useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(amount > 1 ether);
        vm.assume(amount <= MAX_STAKING_TOKENS);
        address escrowAddress = address(escrow);
        
        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        vm.expectRevert(abi.encodeWithSelector(
            IHorizonStakingMain.HorizonStakingInvalidProvision.selector,
            users.indexer,
            subgraphDataServiceAddress
        ));
        payments.collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, 1);
    }
}
