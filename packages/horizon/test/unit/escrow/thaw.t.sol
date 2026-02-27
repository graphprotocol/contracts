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

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            users.gateway,
            users.verifier,
            users.indexer
        );
        assertEq(account.balance - account.tokensThawing, 0);
    }

    function testThaw_Tokens_SuccesiveCalls_PreservesTimer(uint256 amount) public useGateway {
        amount = bound(amount, 3, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2;
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10;

        (, address msgSender, ) = vm.readCallers();

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        // Advance time — second thaw should preserve the original timer
        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        escrow.thaw(users.verifier, users.indexer, secondAmountToThaw);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, secondAmountToThaw);
        assertEq(account.thawEndTimestamp, expectedThawEnd, "Timer should be preserved, not reset");
    }

    function testThaw_Tokens_SuccesiveCalls_ResetsTimerOnIncrease(uint256 amount) public useGateway {
        amount = bound(amount, 10, type(uint256).max - 10);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10; // ~10% of amount
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2; // ~50% of amount

        (, address msgSender, ) = vm.readCallers();

        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);

        // Advance time — second thaw with larger amount should reset the timer
        vm.warp(block.timestamp + 1 hours);

        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        escrow.thaw(users.verifier, users.indexer, secondAmountToThaw);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, secondAmountToThaw);
        assertEq(account.thawEndTimestamp, expectedThawEnd, "Timer should reset on increase");
    }

    function testThaw_ZeroAmountCancelsAll(uint256 amount) public useGateway useDeposit(amount) {
        escrow.thaw(users.verifier, users.indexer, amount);

        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, amount);

        // thaw(0) cancels all thawing — event should reflect cleared state
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, 0, 0);
        escrow.thaw(users.verifier, users.indexer, 0);

        account = escrow.getEscrowAccount(msgSender, users.verifier, users.indexer);
        assertEq(account.tokensThawing, 0);
        assertEq(account.thawEndTimestamp, 0);
    }

    function testThaw_CapsAtBalance(uint256 amount, uint256 overAmount) public useGateway useDeposit(amount) {
        overAmount = bound(overAmount, amount + 1, type(uint256).max);

        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, overAmount);
        assertEq(tokensThawing, amount, "Should cap at balance");

        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, amount);
    }

    function testThaw_CancelRequest(uint256 amount) public useGateway useDeposit(amount) {
        _thawEscrow(users.verifier, users.indexer, amount);
        _cancelThawEscrow(users.verifier, users.indexer);
    }

    function testThaw_CancelRequest_NoopWhenNotThawing(uint256 amount) public useGateway useDeposit(amount) {
        uint256 tokensThawing = escrow.cancelThaw(users.verifier, users.indexer);
        assertEq(tokensThawing, 0);
    }

    function testThaw_NoopWhenRequestedEqualsCurrentThawing(uint256 amount) public useGateway useDeposit(amount) {
        // First thaw
        escrow.thaw(users.verifier, users.indexer, amount);

        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory accountBefore = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );

        // Same amount again should be a no-op — returns early without state change
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, amount);
        assertEq(tokensThawing, amount);

        IPaymentsEscrow.EscrowAccount memory accountAfter = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(accountAfter.tokensThawing, accountBefore.tokensThawing);
        assertEq(accountAfter.thawEndTimestamp, accountBefore.thawEndTimestamp);
    }

    /*
     * evenIfTimerReset = false tests
     */

    function testThaw_EvenIfTimerResetFalse_ProceedsWithNewThaw(uint256 amount) public useGateway useDeposit(amount) {
        // When no existing thaw, evenIfTimerReset=false should proceed normally
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, amount, expectedThawEnd);
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, amount, false);
        assertEq(tokensThawing, amount);
    }

    function testThaw_EvenIfTimerResetFalse_ProceedsWithDecrease(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 2 - 1) / 2; // ~50%
        uint256 secondAmountToThaw = (amount + 10 - 1) / 10; // ~10%

        // Thaw first amount
        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        vm.warp(block.timestamp + 1 hours);

        // Decrease with evenIfTimerReset=false should proceed and preserve timer
        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(tokensThawing, secondAmountToThaw);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.thawEndTimestamp, expectedThawEnd, "Timer should be preserved on decrease");
    }

    function testThaw_EvenIfTimerResetFalse_SkipsIncreaseWhenTimerWouldReset(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10; // ~10%
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2; // ~50%

        // Thaw first amount
        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);
        uint256 originalThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;

        // Advance time so timer would change
        vm.warp(block.timestamp + 1 hours);

        // Increase with evenIfTimerReset=false should be a no-op
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(tokensThawing, firstAmountToThaw, "Should return current thawing, not new amount");

        // State should be unchanged
        (, address msgSender, ) = vm.readCallers();
        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, firstAmountToThaw);
        assertEq(account.thawEndTimestamp, originalThawEnd, "Timer should remain unchanged");
    }

    function testThaw_EvenIfTimerResetFalse_ProceedsWhenTimerUnchanged(uint256 amount) public useGateway {
        amount = bound(amount, 10, MAX_STAKING_TOKENS);
        _depositTokens(users.verifier, users.indexer, amount);

        uint256 firstAmountToThaw = (amount + 10 - 1) / 10; // ~10%
        uint256 secondAmountToThaw = (amount + 2 - 1) / 2; // ~50%

        // Thaw first amount
        escrow.thaw(users.verifier, users.indexer, firstAmountToThaw);

        // Increase immediately in the same block — timer wouldn't change
        (, address msgSender, ) = vm.readCallers();
        uint256 expectedThawEnd = block.timestamp + WITHDRAW_ESCROW_THAWING_PERIOD;
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, secondAmountToThaw, expectedThawEnd);
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, secondAmountToThaw, false);
        assertEq(tokensThawing, secondAmountToThaw, "Should proceed when timer unchanged");
    }

    function testThaw_EvenIfTimerResetFalse_CancelsThawing(uint256 amount) public useGateway useDeposit(amount) {
        // Thaw first
        escrow.thaw(users.verifier, users.indexer, amount);

        // Cancel (thaw 0) with evenIfTimerReset=false should still work (decrease path)
        (, address msgSender, ) = vm.readCallers();
        vm.expectEmit(address(escrow));
        emit IPaymentsEscrow.Thawing(msgSender, users.verifier, users.indexer, 0, 0);
        uint256 tokensThawing = escrow.thaw(users.verifier, users.indexer, 0, false);
        assertEq(tokensThawing, 0);

        IPaymentsEscrow.EscrowAccount memory account = escrow.getEscrowAccount(
            msgSender,
            users.verifier,
            users.indexer
        );
        assertEq(account.tokensThawing, 0);
        assertEq(account.thawEndTimestamp, 0);
    }
}
