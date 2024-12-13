// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import { IPaymentsEscrow } from "../../contracts/interfaces/IPaymentsEscrow.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "../../contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../shared/payments-escrow/PaymentsEscrowShared.t.sol";
import { PPMMath } from "../../contracts/libraries/PPMMath.sol";

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
        vm.assume(thawAmount > 0);
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
        uint256 expectedThawEndTimestamp = block.timestamp + withdrawEscrowThawingPeriod;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, collector, receiver, amount, expectedThawEndTimestamp);
        escrow.thaw(collector, receiver, amount);

        (, uint256 amountThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(msgSender, collector, receiver);
        assertEq(amountThawing, amount);
        assertEq(thawEndTimestamp, expectedThawEndTimestamp);
    }

    function _cancelThawEscrow(address collector, address receiver) internal {
        (, address msgSender, ) = vm.readCallers();
        (, uint256 amountThawingBefore, uint256 thawEndTimestampBefore) = escrow.escrowAccounts(msgSender, collector, receiver);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.CancelThaw(msgSender, receiver, amountThawingBefore, thawEndTimestampBefore);
        escrow.cancelThaw(collector, receiver);

        (, uint256 amountThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(msgSender, collector, receiver);
        assertEq(amountThawing, 0);
        assertEq(thawEndTimestamp, 0);
    }

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
        uint256 payerEscrowBalance;
    }

    function _collectEscrow(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _dataServiceCut
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

        {
            (uint256 payerEscrowBalance, , ) = escrow.escrowAccounts(_payer, _collector, _receiver);
            previousBalances.payerEscrowBalance = payerEscrowBalance;
        }

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.EscrowCollected(_payer, _collector, _receiver, _tokens);
        escrow.collect(_paymentType, _payer, _receiver, _tokens, _dataService, _dataServiceCut);

        // Calculate cuts
        // this is nasty but stack is indeed too deep
        uint256 tokensDataService = (_tokens - _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT())).mulPPMRoundUp(
            _dataServiceCut
        );
        uint256 tokensDelegation = 0;
        IHorizonStakingTypes.DelegationPool memory pool = staking.getDelegationPool(_receiver, _dataService);
        if (pool.shares > 0) {
            tokensDelegation = (_tokens - _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT()) - tokensDataService)
                .mulPPMRoundUp(staking.getDelegationFeeCut(_receiver, _dataService, _paymentType));
        }
        uint256 receiverExpectedPayment = _tokens -
            _tokens.mulPPMRoundUp(payments.PROTOCOL_PAYMENT_CUT()) -
            tokensDataService -
            tokensDelegation;

        // After balances
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService),
            payerEscrowBalance: 0
        });
        {
            (uint256 afterPayerEscrowBalance, , ) = escrow.escrowAccounts(_payer, _collector, _receiver);
            afterBalances.payerEscrowBalance = afterPayerEscrowBalance;
        }

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

        // Check payers escrow balance after payment
        assertEq(previousBalances.payerEscrowBalance - _tokens, afterBalances.payerEscrowBalance);
    }
}
