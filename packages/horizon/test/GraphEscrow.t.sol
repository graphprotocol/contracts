// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/GraphEscrow.sol";
import { GraphPayments } from "contracts/GraphPayments.sol";

import "./mocks/MockGRTToken.sol";

contract GraphEscrowTest is Test {
    GraphEscrow escrow;

    Controller controller;
    MockGRTToken token;

    address governor = address(0xA1);
    uint256 initialSupply = 1000000 ether;
    uint256 withdrawEscrowThawingPeriod = 60;

    address sender;
    address receiver;

    // Setup

    function setUp() public {
        vm.prank(governor);
        controller = new Controller();
        token = new MockGRTToken();

        vm.startPrank(governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        vm.stopPrank();

        escrow = new GraphEscrow(address(controller), withdrawEscrowThawingPeriod);

        sender = address(0xB1);
        receiver = address(0xB2);
    }

    function testDeposit() public {
        token.mint(sender, 10000 ether);
        vm.startPrank(sender);
        token.approve(address(escrow), 1000 ether);
        escrow.deposit(receiver, 1000 ether);
        vm.stopPrank();


        (uint256 receiverEscrowBalance,,) = escrow.escrowAccounts(sender, receiver);
        assertEq(receiverEscrowBalance, 1000 ether);
    }
}