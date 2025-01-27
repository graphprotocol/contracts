// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";
import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowWithdrawTest is GraphEscrowTest {

    /*
     * TESTS
     */

    function testWithdraw_Tokens(
        uint256 amount, 
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        // advance time
        skip(withdrawEscrowThawingPeriod + 1);

        _withdrawEscrow(users.verifier, users.indexer);
        vm.stopPrank();
    }

    function testWithdraw_RevertWhen_NotThawing(uint256 amount) public useGateway useDeposit(amount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.withdraw(users.verifier, users.indexer);
    }

    function testWithdraw_RevertWhen_StillThawing(
        uint256 amount,
        uint256 thawAmount
    ) public useGateway depositAndThawTokens(amount, thawAmount) {
        bytes memory expectedError = abi.encodeWithSignature("PaymentsEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + withdrawEscrowThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.withdraw(users.verifier, users.indexer);
    }

    function testWithdraw_BalanceAfterCollect(
        uint256 amountDeposited,
        uint256 amountThawed,
        uint256 amountCollected
    ) public useGateway depositAndThawTokens(amountDeposited, amountThawed) {
        vm.assume(amountCollected > 0);
        vm.assume(amountCollected <= amountDeposited);

        // burn some tokens to prevent overflow
        resetPrank(users.indexer);
        token.burn(MAX_STAKING_TOKENS);

        // collect
        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amountCollected,
            subgraphDataServiceAddress,
            0
        );

        // Advance time to simulate the thawing period
        skip(withdrawEscrowThawingPeriod + 1);

        // withdraw the remaining thawed balance
        resetPrank(users.gateway);
        _withdrawEscrow(users.verifier, users.indexer);
    }
}