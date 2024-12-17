// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";

contract GraphEscrowGettersTest is GraphEscrowTest {
    /*
     * TESTS
     */

    function testGetBalance(uint256 amount) public useGateway useDeposit(amount) {
        uint256 balance = escrow.getBalance(users.gateway, users.verifier, users.indexer);
        assertEq(balance, amount);
    }

    function testGetBalance_WhenThawing(
        uint256 amountDeposit,
        uint256 amountThawing
    ) public useGateway useDeposit(amountDeposit) {
        vm.assume(amountThawing > 0);
        vm.assume(amountDeposit >= amountThawing);

        // thaw some funds
        _thawEscrow(users.verifier, users.indexer, amountThawing);

        uint256 balance = escrow.getBalance(users.gateway, users.verifier, users.indexer);
        assertEq(balance, amountDeposit - amountThawing);
    }

    function testGetBalance_WhenCollectedOverThawing(
        uint256 amountDeposit,
        uint256 amountThawing,
        uint256 amountCollected
    ) public useGateway useDeposit(amountDeposit) {
        vm.assume(amountThawing > 0);
        vm.assume(amountDeposit > 0);
        vm.assume(amountDeposit >= amountThawing);
        vm.assume(amountDeposit >= amountCollected);
        vm.assume(amountDeposit - amountCollected < amountThawing);

        // thaw some funds
        _thawEscrow(users.verifier, users.indexer, amountThawing);

        // users start with max uint256 balance so we burn to avoid overflow
        // TODO: we should modify all tests to consider users have a max balance thats less than max uint256
        resetPrank(users.indexer);
        token.burn(amountCollected);

        // collect some funds to get the balance of the account below the amount thawing
        resetPrank(users.verifier);
        _collectEscrow(
            IGraphPayments.PaymentTypes.QueryFee,
            users.gateway,
            users.indexer,
            amountCollected,
            subgraphDataServiceAddress,
            0
        );

        // balance should always be 0 since thawing funds > available funds
        uint256 balance = escrow.getBalance(users.gateway, users.verifier, users.indexer);
        assertEq(balance, 0);
    }
}
