// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/GraphEscrow.sol";
import { GraphPayments } from "contracts/GraphPayments.sol";
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

    // Tests

    function testApproveCollector() public {
        vm.prank(sender);
        payments.approveCollector(dataService);

        (bool authorized, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testThawCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService);
        payments.thawCollector(dataService);
        vm.stopPrank();

        (bool authorized, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);
    }

    function testCancelThawCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService);
        payments.thawCollector(dataService);
        vm.stopPrank();

        (bool authorized, uint256 thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, block.timestamp + revokeCollectorThawingPeriod);

        vm.prank(sender);
        payments.cancelThawCollector(dataService);

        (authorized, thawEndTimestamp) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, true);
        assertEq(thawEndTimestamp, 0);
    }

    function testRevokeCollector() public {
        vm.startPrank(sender);
        payments.approveCollector(dataService);
        payments.thawCollector(dataService);
        skip(revokeCollectorThawingPeriod + 1);
        payments.revokeCollector(dataService);
        vm.stopPrank();

        (bool authorized,) = payments.authorizedCollectors(sender, dataService);
        assertEq(authorized, false);
    }

    function testCollect() public {
        vm.prank(sender);
        payments.approveCollector(dataService);

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
}