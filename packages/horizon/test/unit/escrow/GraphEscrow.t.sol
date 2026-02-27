// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../shared/payments-escrow/PaymentsEscrowShared.t.sol";
import { PPMMath } from "../../../contracts/libraries/PPMMath.sol";

contract GraphEscrowTest is HorizonStakingSharedTest, PaymentsEscrowSharedTest {
    using PPMMath for uint256;

    /*
     * MODIFIERS
     */

    modifier approveEscrow(uint256 tokens) {
        _approveEscrow(tokens);
        _;
    }

    modifier useDeposit(uint256 tokens) {
        vm.assume(tokens > 0);
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, tokens);
        _;
    }

    modifier depositAndThawTokens(uint256 amount, uint256 thawAmount) {
        vm.assume(amount > 0);
        vm.assume(thawAmount > 0);
        vm.assume(amount <= MAX_STAKING_TOKENS);
        vm.assume(amount > thawAmount);
        _depositTokens(users.verifier, users.indexer, amount);
        escrow.thaw(users.verifier, users.indexer, thawAmount);
        _;
    }

    /*
     * HELPERS
     */

    function _approveEscrow(uint256 tokens) internal {
        token.approve(address(escrow), tokens);
    }

    function _thawEscrow(address collector, address receiver, uint256 amount) internal {
        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory accountBefore = escrow.getEscrowAccount(msgSender, collector, receiver);

        // Timer resets when increasing, preserves when decreasing, starts when new
        uint256 expectedThawEndTimestamp = (accountBefore.thawEndTimestamp == 0 || amount > accountBefore.tokensThawing)
            ? block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD
            : accountBefore.thawEndTimestamp;

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, collector, receiver, amount, expectedThawEndTimestamp);
        escrow.thaw(collector, receiver, amount);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(msgSender, collector, receiver);
        assertEq(account.tokensThawing, amount);
        assertEq(account.thawEndTimestamp, expectedThawEndTimestamp);
    }

    function _cancelThawEscrow(address collector, address receiver) internal {
        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory accountBefore = escrow.getEscrowAccount(msgSender, collector, receiver);

        if (accountBefore.tokensThawing != 0) {
            vm.expectEmit(address(escrow));
            emit IPaymentsEscrow.Thawing(msgSender, collector, receiver, 0, 0);
        }
        escrow.cancelThaw(collector, receiver);

        IPaymentsEscrow.EscrowAccount memory accountAfter = escrow.getEscrowAccount(msgSender, collector, receiver);
        assertEq(accountAfter.tokensThawing, 0);
        assertEq(accountAfter.thawEndTimestamp, 0);
    }

    function _withdrawEscrow(address collector, address receiver) internal {
        (, address msgSender, ) = vm.readCallers();

        IPaymentsEscrow.EscrowAccount memory accountBefore = escrow.getEscrowAccount(msgSender, collector, receiver);
        uint256 tokenBalanceBeforeSender = token.balanceOf(msgSender);
        uint256 tokenBalanceBeforeEscrow = token.balanceOf(address(escrow));

        uint256 expectedWithdraw = accountBefore.tokensThawing;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Withdraw(msgSender, collector, receiver, expectedWithdraw);
        uint256 tokens = escrow.withdraw(collector, receiver);
        assertEq(tokens, expectedWithdraw);

        IPaymentsEscrow.EscrowAccount memory accountAfter = escrow.getEscrowAccount(msgSender, collector, receiver);

        assertEq(accountAfter.balance, accountBefore.balance - expectedWithdraw);
        assertEq(accountAfter.tokensThawing, 0);
        assertEq(accountAfter.thawEndTimestamp, 0);

        assertEq(token.balanceOf(msgSender), tokenBalanceBeforeSender + expectedWithdraw);
        assertEq(token.balanceOf(address(escrow)), tokenBalanceBeforeEscrow - expectedWithdraw);
    }

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
        uint256 payerEscrowBalance;
    }

    struct CollectTokensData {
        uint256 tokensProtocol;
        uint256 tokensDataService;
        uint256 tokensDelegation;
        uint256 receiverExpectedPayment;
    }

    function _collectEscrow(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _dataServiceCut,
        address _paymentsDestination
    ) internal {
        (, address _collector, ) = vm.readCallers();

        // Previous balances
        CollectPaymentData memory previousBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService),
            payerEscrowBalance: 0
        });
        CollectTokensData memory collectTokensData = CollectTokensData({
            tokensProtocol: 0,
            tokensDataService: 0,
            tokensDelegation: 0,
            receiverExpectedPayment: 0
        });

        previousBalances.payerEscrowBalance = escrow.getEscrowAccount(_payer, _collector, _receiver).balance;

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.EscrowCollected(
            _paymentType,
            _payer,
            _collector,
            _receiver,
            _tokens,
            _paymentsDestination
        );
        escrow.collect(_paymentType, _payer, _receiver, _tokens, _dataService, _dataServiceCut, _paymentsDestination);

        // Calculate cuts
        // this is nasty but stack is indeed too deep
        collectTokensData.tokensProtocol = _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT());
        collectTokensData.tokensDataService = (_tokens - collectTokensData.tokensProtocol).mulPPMRoundUp(
            _dataServiceCut
        );

        IHorizonStakingTypes.DelegationPool memory pool = staking.getDelegationPool(_receiver, _dataService);
        if (pool.shares > 0) {
            collectTokensData.tokensDelegation = (_tokens -
                collectTokensData.tokensProtocol -
                collectTokensData.tokensDataService).mulPPMRoundUp(
                    staking.getDelegationFeeCut(_receiver, _dataService, _paymentType)
                );
        }
        collectTokensData.receiverExpectedPayment =
            _tokens -
            collectTokensData.tokensProtocol -
            collectTokensData.tokensDataService -
            collectTokensData.tokensDelegation;

        // After balances
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService),
            payerEscrowBalance: 0
        });
        afterBalances.payerEscrowBalance = escrow.getEscrowAccount(_payer, _collector, _receiver).balance;

        // Check receiver balance after payment
        assertEq(
            afterBalances.receiverBalance - previousBalances.receiverBalance,
            collectTokensData.receiverExpectedPayment
        );
        assertEq(token.balanceOf(address(payments)), 0);

        // Check delegation pool balance after payment
        assertEq(
            afterBalances.delegationPoolBalance - previousBalances.delegationPoolBalance,
            collectTokensData.tokensDelegation
        );

        // Check that the escrow account has been updated
        assertEq(previousBalances.escrowBalance, afterBalances.escrowBalance + _tokens);

        // Check that payments balance didn't change
        assertEq(previousBalances.paymentsBalance, afterBalances.paymentsBalance);

        // Check data service balance after payment
        assertEq(
            afterBalances.dataServiceBalance - previousBalances.dataServiceBalance,
            collectTokensData.tokensDataService
        );

        // Check payers escrow balance after payment
        assertEq(previousBalances.payerEscrowBalance - _tokens, afterBalances.payerEscrowBalance);
    }
}
