// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../../contracts/interfaces/IPaymentsEscrow.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowPausedTest is GraphEscrowTest {

    /*
     * MODIFIERS
     */

    modifier usePaused(bool paused) {
        address msgSender;
        (, msgSender,) = vm.readCallers();
        resetPrank(users.governor);
        controller.setPaused(paused);
        resetPrank(msgSender);
        _;
    }

    /*
     * TESTS
     */

    // Escrow

    function testPaused_RevertWhen_Deposit(uint256 tokens) public useGateway usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.deposit(users.indexer, tokens);
    }

    function testPaused_RevertWhen_DepositTo(uint256 tokens) public usePaused(true) {
        resetPrank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.depositTo(users.gateway, users.indexer, tokens);
    }

    function testPaused_RevertWhen_ThawTokens(uint256 tokens) public useGateway useDeposit(tokens) usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.thaw(users.indexer, tokens);
    }

    function testPaused_RevertWhen_WithdrawTokens(
        uint256 tokens, 
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(tokens, thawAmount) usePaused(true) {
        // advance time
        skip(withdrawEscrowThawingPeriod + 1);

        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.withdraw(users.indexer);
    }

    // Collect

    function testPaused_RevertWhen_CollectTokens(uint256 tokens, uint256 tokensDataService) public usePaused(true) {
        resetPrank(users.verifier);
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.collect(IGraphPayments.PaymentTypes.QueryFee, users.gateway, users.indexer, tokens, subgraphDataServiceAddress, tokensDataService);
    }

    // Collectors

    function testPaused_RevertWhen_ApproveCollector(uint256 tokens) public useGateway usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.approveCollector(users.verifier, tokens);
    }

    function testPaused_RevertWhen_ThawCollector(uint256 tokens) public useGateway useCollector(tokens) usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.thawCollector(users.verifier);
    }

    function testPaused_RevertWhen_CancelThawCollector(uint256 tokens) public useGateway useCollector(tokens) usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.cancelThawCollector(users.verifier);
    }

    function testPaused_RevertWhen_RevokeCollector(uint256 tokens) public useGateway useCollector(tokens) usePaused(true) {
        vm.expectRevert(abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowIsPaused.selector));
        escrow.revokeCollector(users.verifier);
    }
}