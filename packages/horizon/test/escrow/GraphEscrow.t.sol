// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import { IPaymentsEscrow } from "../../contracts/interfaces/IPaymentsEscrow.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";
import { PaymentsEscrowSharedTest } from "../shared/payments-escrow/PaymentsEscrowShared.t.sol";

contract GraphEscrowTest is HorizonStakingSharedTest, PaymentsEscrowSharedTest {
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

    struct CollectPaymentData {
        uint256 escrowBalance;
        uint256 paymentsBalance;
        uint256 receiverBalance;
        uint256 delegationPoolBalance;
        uint256 dataServiceBalance;
    }

    function _collectEscrow(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        address _receiver,
        uint256 _tokens,
        address _dataService,
        uint256 _tokensDataService
    ) internal {
        (, address _collector, ) = vm.readCallers();

        // Previous balances
        (uint256 previousPayerEscrowBalance, , ) = escrow.escrowAccounts(_payer, _collector, _receiver);
        CollectPaymentData memory previousBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService)
        });

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.EscrowCollected(_payer, _collector, _receiver, _tokens);
        escrow.collect(_paymentType, _payer, _receiver, _tokens, _dataService, _tokensDataService);

        // Calculate cuts
        uint256 protocolPaymentCut = payments.PROTOCOL_PAYMENT_CUT();
        uint256 delegatorCut = staking.getDelegationFeeCut(_receiver, _dataService, _paymentType);

        // After balances
        (uint256 afterPayerEscrowBalance, , ) = escrow.escrowAccounts(_payer, _collector, _receiver);
        CollectPaymentData memory afterBalances = CollectPaymentData({
            escrowBalance: token.balanceOf(address(escrow)),
            paymentsBalance: token.balanceOf(address(payments)),
            receiverBalance: token.balanceOf(_receiver),
            delegationPoolBalance: staking.getDelegatedTokensAvailable(_receiver, _dataService),
            dataServiceBalance: token.balanceOf(_dataService)
        });

        // Check receiver balance after payment
        uint256 receiverExpectedPayment = _tokens -
            _tokensDataService -
            (_tokens * protocolPaymentCut) /
            MAX_PPM -
            (_tokens * delegatorCut) /
            MAX_PPM;
        assertEq(afterBalances.receiverBalance - previousBalances.receiverBalance, receiverExpectedPayment);
        assertEq(token.balanceOf(address(payments)), 0);

        // Check delegation pool balance after payment
        assertEq(
            afterBalances.delegationPoolBalance - previousBalances.delegationPoolBalance,
            (_tokens * delegatorCut) / MAX_PPM
        );

        // Check that the escrow account has been updated
        assertEq(previousBalances.escrowBalance, afterBalances.escrowBalance + _tokens);

        // Check that payments balance didn't change
        assertEq(previousBalances.paymentsBalance, afterBalances.paymentsBalance);

        // Check data service balance after payment
        assertEq(afterBalances.dataServiceBalance - previousBalances.dataServiceBalance, _tokensDataService);

        // Check payers escrow balance after payment
        assertEq(previousPayerEscrowBalance - _tokens, afterPayerEscrowBalance);
    }
}
