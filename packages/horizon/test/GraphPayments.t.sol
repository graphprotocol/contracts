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

        protocolPaymentCut = deployments.protocolPaymentCut();

        sender = address(0xA1);
        dataService = address(0xA2);
    }

    // Collect tests

    function testCollect() public {
        address indexer = address(0xA3);
        uint256 amount = 1000 ether;
        address escrowAddress = address(escrow);

        vm.startPrank(escrowAddress);
        token.mint(escrowAddress, amount);
        token.approve(address(payments), amount);

        uint256 dataServiceCut = 30 ether; // 3%
        payments.collect(indexer, dataService, amount, IGraphPayments.PaymentType.IndexingFees, dataServiceCut);
        vm.stopPrank();

        uint256 indexerBalance = token.balanceOf(indexer);
        assertEq(indexerBalance, 910 ether);

        uint256 dataServiceBalance = token.balanceOf(dataService);
        assertEq(dataServiceBalance, 30 ether);

        uint256 delegatorBalance = staking.delegationPool(indexer);
        assertEq(delegatorBalance, 50 ether);
    }
}
