// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
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
        assertEq(thawEndTimestamp, block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD);
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

    function testThaw_AlwaysResetsTimerOnSuccessiveCalls(uint256 amount) public useGateway {
        amount = bound(amount, 3, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2;
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10;

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);

        // Advance time — simple thaw always resets the timer, even on decrease
        vm.warp(block.timestamp + 1 hours);

        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        escrow.thaw(users.verifier, users.indexer, secondAmountToThaw);

        (, uint256 amountThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawing, secondAmountToThaw);
        assertEq(thawEndTimestamp, expectedThawEnd, "Timer should always reset on simple thaw");
    }

    function testThaw_ResetsTimerOnIncrease(uint256 amount) public useGateway {
        amount = bound(amount, 10, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10;
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2;

        (, address msgSender, ) = vm.readCallers();

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);

        // Advance time — second thaw with larger amount should reset the timer
        vm.warp(block.timestamp + 1 hours);

        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        escrow.thaw(users.verifier, users.indexer, secondAmountToThaw);

        (, uint256 amountThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawing, secondAmountToThaw);
        assertEq(thawEndTimestamp, expectedThawEnd, "Timer should reset on increase");
    }

    /*
     * adjustThaw tests
     */

    function testAdjustThaw_CapsAtBalance(uint256 amount, uint256 overAmount) public useGateway useDeposit(amount) {
        overAmount = bound(overAmount, amount + 1, type(uint256).max);

        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, overAmount, true);
        assertEq(amountThawing, amount, "Should cap at balance");

        (, address msgSender, ) = vm.readCallers();
        (, uint256 storedThawing, ) = escrow.escrowAccounts(msgSender, users.verifier, users.indexer);
        assertEq(storedThawing, amount);
    }

    function testAdjustThaw_ZeroAmountCancelsAll(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.verifier, users.indexer, amount);

        (, address msgSender, ) = vm.readCallers();
        (, uint256 amountThawingBefore, uint256 thawEndTimestampBefore) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawingBefore, amount);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.CancelThaw(
            msgSender,
            users.verifier,
            users.indexer,
            amountThawingBefore,
            thawEndTimestampBefore
        );
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, 0, true);
        assertEq(amountThawing, 0);

        (, uint256 amountThawingAfter, uint256 thawEndTimestampAfter) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawingAfter, 0);
        assertEq(thawEndTimestampAfter, 0);
    }

    function testAdjustThaw_NoopWhenRequestedEqualsCurrentThawing(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.verifier, users.indexer, amount);

        (, address msgSender, ) = vm.readCallers();
        (, uint256 amountThawingBefore, uint256 thawEndTimestampBefore) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );

        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, amount, true);
        assertEq(amountThawing, amount);

        (, uint256 amountThawingAfter, uint256 thawEndTimestampAfter) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawingAfter, amountThawingBefore);
        assertEq(thawEndTimestampAfter, thawEndTimestampBefore);
    }

    function testAdjustThaw_PreservesTimerOnDecrease(uint256 amount) public useGateway {
        amount = bound(amount, 3, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2;
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10;

        (, address msgSender, ) = vm.readCallers();

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, secondAmountToThaw, true);
        assertEq(amountThawing, secondAmountToThaw);

        (, uint256 storedThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(storedThawing, secondAmountToThaw);
        assertEq(thawEndTimestamp, expectedThawEnd, "Timer should be preserved on decrease");
    }

    /*
     * adjustThaw evenIfTimerReset = false tests
     */

    function testAdjustThaw_EvenIfTimerResetFalse_ProceedsWithNewThaw(
        uint256 amount
    ) public useGateway useDeposit(amount) {
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, amount, expectedThawEnd);
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, amount, false);
        assertEq(amountThawing, amount);
    }

    function testAdjustThaw_EvenIfTimerResetFalse_ProceedsWithDecrease(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2;
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10;

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.warp(block.timestamp + 1 hours);

        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(amountThawing, secondAmountToThaw);

        (, , uint256 thawEndTimestamp) = escrow.escrowAccounts(msgSender, users.verifier, users.indexer);
        assertEq(thawEndTimestamp, expectedThawEnd, "Timer should be preserved on decrease");
    }

    function testAdjustThaw_EvenIfTimerResetFalse_SkipsIncreaseWhenTimerWouldReset(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10;
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2;

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 originalThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.warp(block.timestamp + 1 hours);

        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(amountThawing, firstAmountToThaw, "Should return current thawing, not new amount");

        (, address msgSender, ) = vm.readCallers();
        (, uint256 storedThawing, uint256 thawEndTimestamp) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(storedThawing, firstAmountToThaw);
        assertEq(thawEndTimestamp, originalThawEnd, "Timer should remain unchanged");
    }

    function testAdjustThaw_EvenIfTimerResetFalse_ProceedsWhenTimerUnchanged(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10;
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2;

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);

        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thaw(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(amountThawing, secondAmountToThaw, "Should proceed when timer unchanged");
    }

    function testAdjustThaw_EvenIfTimerResetFalse_CancelsThawing(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.verifier, users.indexer, amount);

        (, address msgSender, ) = vm.readCallers();
        (, uint256 amountThawingBefore, uint256 thawEndTimestampBefore) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.CancelThaw(
            msgSender,
            users.verifier,
            users.indexer,
            amountThawingBefore,
            thawEndTimestampBefore
        );
        uint256 amountThawing = escrow.adjustThaw(users.verifier, users.indexer, 0, false);
        assertEq(amountThawing, 0);

        (, uint256 amountThawingAfter, uint256 thawEndTimestampAfter) = escrow.escrowAccounts(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(amountThawingAfter, 0);
        assertEq(thawEndTimestampAfter, 0);
    }
}
