// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/escrow/GraphEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { IGraphPayments } from "contracts/interfaces/IGraphPayments.sol";

import "./GraphDeployments.t.sol";
import "./mocks/MockHorizonStaking.sol";
import "./mocks/MockGRTToken.sol";

contract GraphPaymentsTest is Test {
    GraphDeployments deployments;
    GraphPayments payments;
    Controller controller;
    MockGRTToken token;
    GraphEscrow escrow;
    MockHorizonStaking staking;

    address governor;

    uint256 revokeCollectorThawingPeriod;
    uint256 protocolPaymentCut;

    address sender;
    address dataService;

    // Setup

    function setUp() public {
        deployments = new GraphDeployments();

        payments = deployments.payments();
        controller = deployments.controller();
        token = deployments.token();
        escrow = deployments.escrow();
        staking = deployments.staking();
        governor = deployments.governor();

        revokeCollectorThawingPeriod = deployments.revokeCollectorThawingPeriod();
        protocolPaymentCut = deployments.protocolPaymentCut();

        sender = address(0xA1);
        dataService = address(0xA2);
    }

    // Approve tests

    function testApproveCollector() public {
        vm.prank(sender);
        payments.approveCollector(dataService, 1000 ether);

        (bool authorized,, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    // Thaw tests

    function testThawCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        payments.thawCollector(dataService);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    // Cancel thaw tests

    function testCancelThawCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        payments.thawCollector(dataService);
        vm.stopPrank();

        (bool authorized,, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        vm.prank(sender);
        payments.cancelThawCollector(dataService);

        (authorized,, thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testCancel_RevertWhen_CollectorIsNotThawing() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphPaymentsNotThawing()");
        vm.expectRevert(expectedError);
        payments.cancelThawCollector(dataService);
        vm.stopPrank();
    }

    // Revoke tests

    function testRevokeCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        payments.thawCollector(dataService);
        skip(revokeCollectorThawingPeriod + 1);
        payments.revokeCollector(dataService);
        vm.stopPrank();

        (bool authorized,,) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, false);
    }

    function testRevoke_RevertWhen_CollectorIsNotThawing() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        bytes memory expectedError = abi.encodeWithSignature("GraphPaymentsNotThawing()");
        vm.expectRevert(expectedError);
        payments.revokeCollector(dataService);
        vm.stopPrank();
    }

    function testRevoke_RevertWhen_CollectorIsStillThawing() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService, 1000 ether);
        payments.thawCollector(dataService);
        bytes memory expectedError = abi.encodeWithSignature("GraphPaymentsStillThawing(uint256,uint256)", block.timestamp, block.timestamp + revokeCollectorThawingPeriod);
        vm.expectRevert(expectedError);
        payments.revokeCollector(dataService);
        vm.stopPrank();
    }

    // Collect tests

    function testCollect() public {
        vm.prank(sender);
        payments.approveCollector(dataService, 1000 ether);

        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        token.mint(sender, amount);
        vm.startPrank(sender);
        token.approve(address(escrow), amount);
        escrow.deposit(indexer, amount);
        vm.stopPrank();

        vm.startPrank(dataService);
        uint256 dataServiceCut = 30000; // 3%
        payments.collect(sender, indexer, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();

        uint256 indexerBalance = token.balanceOf(indexer);
        assertEq(indexerBalance, 910 ether);

        uint256 dataServiceBalance = token.balanceOf(dataService);
        assertEq(dataServiceBalance, 30 ether);

        uint256 delegatorBalance = staking.delegationPool(indexer);
        assertEq(delegatorBalance, 50 ether);
    }

    function testCollect_RevertWhen_CollectorNotAuthorized() public {
        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        vm.startPrank(dataService);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphPaymentsCollectorNotAuthorized(address,address)", sender, dataService);
        vm.expectRevert(expectedError);
        payments.collect(sender, indexer, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }

    function testCollect_RevertWhen_CollectorHasInsufficientAmount() public {
        vm.prank(sender);
        payments.approveCollector(dataService, 100 ether);

        address indexer = address(0xA3);
        uint256 amount = 1000 ether;

        token.mint(sender, amount);
        vm.startPrank(sender);
        token.approve(address(escrow), amount);
        escrow.deposit(indexer, amount);
        vm.stopPrank();

        vm.startPrank(dataService);
        uint256 dataServiceCut = 30000; // 3%
        bytes memory expectedError = abi.encodeWithSignature("GraphPaymentsCollectorInsufficientAmount(uint256,uint256)", 100 ether, 1000 ether);
        vm.expectRevert(expectedError);
        payments.collect(sender, indexer, 1000 ether, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();
    }
}