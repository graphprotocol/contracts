// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStaking.t.sol";

contract GraphPaymentsTest is HorizonStakingSharedTest {

    function testCollect() public {
        // Setup Staking
        uint256 amount = 1000 ether;
        createProvision(amount);
        setDelegationFeeCut(0, 100000);

        address escrowAddress = address(escrow);

        // Add tokens in escrow
        mint(escrowAddress, amount);
        vm.startPrank(escrowAddress);
        approve(address(payments), amount);

        // Collect payments through GraphPayments
        uint256 dataServiceCut = 30 ether; // 3%
        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        payments.collect(users.indexer, subgraphDataServiceAddress, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();

        uint256 indexerBalance = token.balanceOf(users.indexer);
        assertEq(indexerBalance - indexerPreviousBalance, 860 ether);

        uint256 dataServiceBalance = token.balanceOf(subgraphDataServiceAddress);
        assertEq(dataServiceBalance, 30 ether);

        uint256 delegatorBalance = staking.getDelegatedTokensAvailable(users.indexer, subgraphDataServiceAddress);
        assertEq(delegatorBalance, 100 ether);
    }
}
