// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStaking.t.sol";

contract GraphPaymentsTest is HorizonStakingSharedTest {

    function testCollect(
        uint256 amount,
        uint256 tokensDataService
    ) public useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        uint256 tokensProtocol = amount * protocolPaymentCut / MAX_PPM;
        uint256 tokensDelegatoion = amount * delegationFeeCut / MAX_PPM;
        vm.assume(tokensDataService < amount - tokensProtocol - tokensDelegatoion);
        address escrowAddress = address(escrow);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        payments.collect(IGraphPayments.PaymentTypes.QueryFee, users.indexer, amount, subgraphDataServiceAddress, tokensDataService);
        vm.stopPrank();

        uint256 indexerBalance = token.balanceOf(users.indexer);
        uint256 expectedPayment = amount - tokensDataService - tokensProtocol - tokensDelegatoion;
        assertEq(indexerBalance - indexerPreviousBalance, expectedPayment);

        uint256 dataServiceBalance = token.balanceOf(subgraphDataServiceAddress);
        assertEq(dataServiceBalance, tokensDataService);

        uint256 delegatorBalance = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(delegatorBalance, tokensDelegatoion);
    }

    function testCollect_RevertWhen_InsufficientAmount(
        uint256 amount,
        uint256 tokensDataService
    ) public useProvision(amount, 0, 0) useDelegationFeeCut(IGraphPayments.PaymentTypes.QueryFee, delegationFeeCut) {
        vm.assume(tokensDataService <= 10_000_000_000 ether);
        vm.assume(tokensDataService > amount);

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
}
