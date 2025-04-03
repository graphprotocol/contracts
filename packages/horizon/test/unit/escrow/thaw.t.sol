// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowThawTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testThaw_PartialBalanceThaw(
        uint256 amountDeposited,
        uint256 amountThawed
    ) public useGateway useDeposit(amountDeposited) {
        vm.assume(amountThawed > 0);
        vm.assume(amountThawed <= amountDeposited);
        _thawEscrow(users.verifier, users.indexer, amountThawed);
    }

    function testThaw_FullBalanceThaw(uint256 amount) public useGateway useDeposit(amount) {
        vm.assume(amount > 0);
        _thawEscrow(users.verifier, users.indexer, amount);

        uint256 availableBalance = escrow.getBalance(users.gateway, users.verifier, users.indexer);
        assertEq(availableBalance, 0);
    }

    function testThaw_Tokens_SuccesiveCalls(uint256 amount) public useGateway {
        amount = bound(amount, 2, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2;
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10;
        _thawEscrow(users.verifier, users.indexer, firstAmountToThaw);
        _thawEscrow(users.verifier, users.indexer, secondAmountToThaw);

        (, address msgSender, ) = vm.readCallers();
        (, uint256 amountThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawing, secondAmountToThaw);
        assertEq(thawEndTimestamp, block.timestamp + withdrawEscrowThawingPeriod);
    }

    function testThaw_Tokens_RevertWhen_AmountIsZero() public useGateway {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowInvalidZeroTokens()");
        vm.expectRevert(expectedError);
        escrow.thaw(users.verifier, users.indexer, 0);
    }

    function testThaw_RevertWhen_InsufficientAmount(
        uint256 amount,
        uint256 overAmount
    ) public useGateway useDeposit(amount) {
        overAmount = bound(overAmount, amount + 1, type(uint256).max);
        bytes memory expectedError = abi.encodeWithSignature(
            "PaymentsEscrowInsufficientBalance(uint256,uint256)",
            amount,
            overAmount
        );
        vm.expectRevert(expectedError);
        escrow.thaw(users.verifier, users.indexer, overAmount);
    }

    function testThaw_CancelRequest(uint256 amount) public useGateway useDeposit(amount) {
        _thawEscrow(users.verifier, users.indexer, amount);
        _cancelThawEscrow(users.verifier, users.indexer);
    }

    function testThaw_CancelRequest_RevertWhen_NoThawing(uint256 amount) public useGateway useDeposit(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThaw(users.verifier, users.indexer);
    }
}
