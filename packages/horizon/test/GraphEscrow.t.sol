// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/escrow/GraphEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { IGraphPayments } from "contracts/interfaces/IGraphPayments.sol";

import "./GraphDeployments.t.sol";
import "./mocks/MockGRTToken.sol";

contract GraphEscrowTest is Test {
    GraphDeployments deployments;
    GraphEscrow escrow;
    Controller controller;
    MockGRTToken token;
    GraphPayments payments;

    address governor = address(0xA2);
    uint256 withdrawEscrowThawingPeriod = 60;
    uint256 revokeCollectorThawingPeriod;

    address sender;
    address receiver;
    address verifier;
    address dataService;

    // Setup

    function setUp() public {
        deployments = new GraphDeployments();

        controller = deployments.controller();
        token = deployments.token();
        escrow = deployments.escrow();
        payments = deployments.payments();

        governor = deployments.governor();
        withdrawEscrowThawingPeriod = deployments.withdrawEscrowThawingPeriod();
        revokeCollectorThawingPeriod = deployments.revokeCollectorThawingPeriod();

        sender = address(0xB1);
        receiver = address(0xB2);
        verifier = address(0xB3);
        dataService = address(0xB4);
    }

    // Collector approve tests

    function testApproveCollector() public {
        vm.prank(sender);
        escrow.approveCollector(verifier, 1000 ether);

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(sender, verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    // Collector thaw tests

    function testThawCollector() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        escrow.thawCollector(verifier);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(sender, verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    // Collector cancel thaw tests

    function testCancelThawCollector() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        escrow.thawCollector(verifier);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = escrow.authorizedCollectors(sender, verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        vm.prank(sender);
        escrow.cancelThawCollector(verifier);

        (authorized,, thawEndTimestamp) = escrow.authorizedCollectors(sender, verifier);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCancel_RevertWhen_CollectorIsNotThawing() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.cancelThawCollector(verifier);
        vm.stopPrank();
    }

    // Collector revoke tests

    function testRevokeCollector() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        escrow.thawCollector(verifier);
        skip(revokeCollectorThawingPeriod + 1);
        escrow.revokeCollector(verifier);
        vm.stopPrank();

        (bool authorized,,) = escrow.authorizedCollectors(sender, verifier);
        assertEq(authorized, false);
    }

    function testRevoke_RevertWhen_CollectorIsNotThawing() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.revokeCollector(verifier);
        vm.stopPrank();
    }

    function testRevoke_RevertWhen_CollectorIsStillThawing() public {
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        escrow.thawCollector(verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.revokeCollector(verifier);
        vm.stopPrank();
    }

    // Deposit tests

    function testDeposit() public {
        token.mint(sender, 10000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        vm.stopPrank();

        (uint256 receiverEscrowBalance,,) = escrow.escrowAccounts(sender, receiver);
        assertEq(receiverEscrowBalance, 1000 ether);
    }

    function testDepositMany() public {
        address otherReceiver = address(0xB3);
        address[] memory receivers = new address[](2);
        receivers[0] = receiver;
        receivers[1] = otherReceiver;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 ether;
        amounts[1] = 2000 ether;

        token.mint(sender, 3000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 3000 ether);
        escrow.depositMany(receivers, amounts);
        vm.stopPrank();

        (uint256 receiverEscrowBalance,,) = escrow.escrowAccounts(sender, receiver);
        assertEq(receiverEscrowBalance, 1000 ether);

        (uint256 otherReceiverEscrowBalance,,) = escrow.escrowAccounts(sender, otherReceiver);
        assertEq(otherReceiverEscrowBalance, 2000 ether);
    }

    function testDepositMany_RevertWhen_InputsLengthMismatch() public {
        address otherReceiver = address(0xB3);
        address[] memory receivers = new address[](2);
        receivers[0] = receiver;
        receivers[1] = otherReceiver;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        token.mint(sender, 1000 ether);
        token.approve(address(escrow), 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInputsLengthMismatch()");
        vm.expectRevert(expectedError);
        vm.prank(sender);
        escrow.depositMany(receivers, amounts);
    }

    // Thaw tests

    function testThaw() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        escrow.thaw(receiver, 100 ether);
        vm.stopPrank();

        (, uint256 amountThawing,uint256 thawEndTimestamp) = escrow.escrowAccounts(sender, receiver);
        assertEq(amountThawing, 100 ether);
        assertEq(thawEndTimestamp, block.timestamp + withdrawEscrowThawingPeriod);
    }

    function testThaw_RevertWhen_InsufficientThawAmount() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientThawAmount()");
        vm.expectRevert(expectedError);
        escrow.thaw(receiver, 0);
        vm.stopPrank();
    }

    function testThaw_RevertWhen_InsufficientAmount() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAmount(uint256,uint256)", 1000 ether, 2000 ether);
        vm.expectRevert(expectedError);
        escrow.thaw(receiver, 2000 ether);
        vm.stopPrank();
    }

    // Withdraw tests

    function testWithdraw() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        escrow.thaw(receiver, 100 ether);

        // advance time
        skip(withdrawEscrowThawingPeriod + 1);

        escrow.withdraw(receiver);
        vm.stopPrank();

        (uint256 receiverEscrowBalance,,) = escrow.escrowAccounts(sender, receiver);
        assertEq(receiverEscrowBalance, 900 ether);
    }

    function testWithdraw_RevertWhen_NotThawing() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowNotThawing()");
        vm.expectRevert(expectedError);
        escrow.withdraw(receiver);
        vm.stopPrank();
    }

    function testWithdraw_RevertWhen_StillThawing() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        escrow.thaw(receiver, 100 ether);

        // revert
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowStillThawing(uint256,uint256)", block.timestamp, block.timestamp + withdrawEscrowThawingPeriod);
        vm.expectRevert(expectedError);
        escrow.withdraw(receiver);
        vm.stopPrank();
    }

    // Collect tests

    function testCollect() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        vm.stopPrank();

        vm.prank(verifier);
        escrow.collect(sender, receiver, dataService, 100 ether, IGraphPayments.PaymentType.IndexingFees, 3 ether);

        uint256 indexerBalance = token.balanceOf(receiver);
        assertEq(indexerBalance, 91 ether);
    }

    function testCollect_RevertWhen_CollectorNotAuthorized() public {
        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        vm.startPrank(verifier);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorNotAuthorized(address,address)", sender, verifier);
        vm.expectRevert(expectedError);
        escrow.collect(sender, indexer, dataService, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_CollectorHasInsufficientAmount() public {
        vm.prank(sender);
        escrow.approveCollector(verifier, 100 ether);

        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        token.mint(sender, amount);
        vm.startPrank(sender);
        token.approve(address(escrow), amount);
        escrow.deposit(indexer, amount);
        vm.stopPrank();

        vm.startPrank(verifier);
        uint256 dataServiceCut = 30 ether;
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowCollectorInsufficientAmount(uint256,uint256)", 100 ether, 1000 ether);
        vm.expectRevert(expectedError);
        escrow.collect(sender, indexer, dataService, 1000 ether, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_SenderHasInsufficientAmountInEscrow() public {
        token.mint(sender, 1000 ether);
        vm.startPrank(sender);
        escrow.approveCollector(verifier, 1000 ether);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 100 ether);
        vm.stopPrank();

        vm.prank(verifier);
        bytes memory expectedError = abi.encodeWithSignature("GraphEscrowInsufficientAmount(uint256,uint256)", 100 ether, 200 ether);
        vm.expectRevert(expectedError);
        escrow.collect(sender, receiver, dataService, 200 ether, IGraphPayments.PaymentType.IndexingFees, 3 ether);
        vm.stopPrank();
    }
}