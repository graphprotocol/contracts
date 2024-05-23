// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

contract GraphEscrowCollectTest is GraphEscrowTest {

    function testCollect_Tokens(uint256 amount, uint256 tokensDataService) public useProvision(amount, 0, 0) useDelegationFeeCut(0, delegationFeeCut) {
        uint256 tokensProtocol = amount * protocolPaymentCut / MAX_PPM;
        uint256 tokensDelegatoion = amount * delegationFeeCut / MAX_PPM;
        vm.assume(tokensDataService < amount - tokensProtocol - tokensDelegatoion);
        
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, amount);
        _depositTokens(amount);
        vm.stopPrank();

        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        vm.prank(users.verifier);
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, tokensDataService);

        uint256 indexerBalance = token.balanceOf(users.indexer);
        uint256 indexerExpectedPayment = amount - tokensDataService - tokensProtocol - tokensDelegatoion;
        assertEq(indexerBalance - indexerPreviousBalance, indexerExpectedPayment);
        assertTrue(true);
    }

    function testCollect_RevertWhen_CollectorNotAuthorized(uint256 amount) public {
        vm.startPrank(users.verifier);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorNotAuthorized(address,address)", users.gateway, users.verifier);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_CollectorHasInsufficientAmount(
        uint256 amount,
        uint256 insufficientAmount
    ) public useGateway useCollector(insufficientAmount) useDeposit(amount) {
        vm.assume(insufficientAmount < amount);

        changePrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAllowance(uint256,uint256)", insufficientAmount, amount);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, 0);
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow(
        uint256 amount, 
        uint256 insufficientAmount
    ) public useGateway useCollector(amount) useDeposit(insufficientAmount)  {
        vm.assume(insufficientAmount < amount);

        changePrank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientBalance(uint256,uint256)", insufficientAmount, amount);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, amount, subgraphDataServiceAddress, 0);
        vm.stopPrank();
    }
}