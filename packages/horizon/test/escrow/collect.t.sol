// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphEscrowTest } from "./GraphEscrow.t.sol";
import { IGraphPayments } from "../../contracts/interfaces/IGraphPayments.sol";

contract GraphEscrowCollectTest is GraphEscrowTest {

    function testCollect() public {
        uint256 amount = 1000 ether;
        createProvision(amount);
        setDelegationFeeCut(0, 100000);

        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 1000 ether);
        vm.stopPrank();

        uint256 indexerPreviousBalance = token.balanceOf(users.indexer);
        vm.prank(users.verifier);
        escrow.collect(IGraphPayments.PaymentTypes.IndexingFee, users.gateway, users.indexer, 100 ether, subgraphDataServiceAddress, 3 ether);

        uint256 indexerBalance = token.balanceOf(users.indexer);
        assertEq(indexerBalance - indexerPreviousBalance, 86 ether);
    }

    function testCollect_RevertWhen_CollectorNotAuthorized() public {
        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        vm.startPrank(users.verifier);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorNotAuthorized(address,address)", users.gateway, users.verifier);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.IndexingFee, users.gateway, indexer, amount, subgraphDataServiceAddress, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_CollectorHasInsufficientAmount() public {
        vm.prank(users.gateway);
        escrow.approveCollector(users.verifier, 100 ether);

        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        vm.startPrank(users.gateway);
        token.approve(address(escrow), amount);
        escrow.deposit(indexer, amount);
        vm.stopPrank();

        vm.startPrank(users.verifier);
        uint256 dataServiceCut = 30 ether;
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorInsufficientAmount(uint256,uint256)", 100 ether, 1000 ether);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.IndexingFee, users.gateway, indexer, 1000 ether, subgraphDataServiceAddress, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow() public {
        vm.startPrank(users.gateway);
        escrow.approveCollector(users.verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(users.indexer, 100 ether);
        vm.stopPrank();

        vm.prank(users.verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAmount(uint256,uint256)", 100 ether, 200 ether);
        vm.expectRevert(expectedError);
        escrow.collect(IGraphPayments.PaymentTypes.IndexingFee, users.gateway, users.indexer, 200 ether, subgraphDataServiceAddress, 3 ether);
        vm.stopPrank();
    }
}