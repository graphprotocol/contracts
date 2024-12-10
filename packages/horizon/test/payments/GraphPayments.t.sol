// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IHorizonStakingMain } from "../../contracts/interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { GraphPayments } from "../../contracts/payments/GraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PPMMath } from "../../contracts/libraries/PPMMath.sol";

contract GraphPaymentsTest is HorizonStakingSharedTest {
    using PPMMath for uint256;

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
        uint256 _dataServiceCut
    ) private {
        // Previous balances
        CollectPaymentData memory previousBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService)
        });

        // Calculate cuts
        uint256 tokensProtocol = _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT());
        uint256 tokensDataService = (_tokens - tokensProtocol).mulPPMRoundUp(_dataServiceCut);
        uint256 tokensDelegation = (_tokens - tokensProtocol - tokensDataService).mulPPMRoundUp(
            staking.getDelegationFeeCut(_receiver, _dataService, _paymentType)
        );

        uint256 receiverExpectedPayment = _tokens - tokensProtocol - tokensDataService - tokensDelegation;

        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(payments));
        emit IGraphPayments.GraphPaymentCollected(
            msgSender,
            _receiver,
            _dataService,
            _tokens,
            tokensProtocol,
            tokensDataService,
            tokensDelegation,
            receiverExpectedPayment
        );
        payments.collect(
            _paymentType,
            _receiver,
            _tokens,
            _dataService,
            _dataServiceCut
        );

        // After balances
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
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
        assertEq(afterBalances.dataServiceBalance - previousBalances.dataServiceBalance, tokensDataService);
    }

    /*
     * TESTS
     */

    function testConstructor_RevertIf_InvalidProtocolPaymentCut(uint256 protocolPaymentCut) public {
        protocolPaymentCut = bound(protocolPaymentCut, MAX_PPM + 1, type(uint256).max);

        resetPrank(users.deployer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphPayments.GraphPaymentsInvalidCut.selector,
            protocolPaymentCut
        );
        vm.expectRevert(expectedError);
        new GraphPayments(address(controller), protocolPaymentCut);
    }

    function testCollect(
        uint256 amount,
        uint256 dataServiceCut,
        uint256 tokensDelegate
    )
        public
        useIndexer
        useProvision(amount, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut)
    {
        dataServiceCut = bound(dataServiceCut, 0, MAX_PPM);
        address escrowAddress = address(escrow);

        // Delegate tokens
        tokensDelegate = bound(tokensDelegate, 1, MAX_STAKING_TOKENS);
        vm.startPrank(users.delegator);
        _delegate(users.indexer, subgraphDataServiceAddress, tokensDelegate, 0);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        _collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut
        );
        vm.stopPrank();
    }

    function testCollect_RevertWhen_InvalidDataServiceCut(
        uint256 amount,
        uint256 dataServiceCut
    )
        public
        useIndexer
        useProvision(amount, 0, 0)
        useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut)
    {
        dataServiceCut = bound(dataServiceCut, MAX_PPM + 1, type(uint256).max);

        resetPrank(users.deployer);
        bytes memory expectedError = abi.encodeWithSelector(
            IGraphPayments.GraphPaymentsInvalidCut.selector,
            dataServiceCut
        );
        vm.expectRevert(expectedError);
        payments.collect(
            IGraphPayments.PaymentTypes.QueryFee,
            users.indexer,
            amount,
            subgraphDataServiceAddress,
            dataServiceCut
        );
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
        address escrowAddress = address(escrow);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidDelegationPool.selector,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IHorizonStakingMain.HorizonStakingInvalidProvision.selector,
                users.indexer,
                subgraphDataServiceAddress
            )
        );
        payments.collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, 1);
    }
}
