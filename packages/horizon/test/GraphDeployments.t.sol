// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";

import { GraphEscrow } from "contracts/escrow/GraphEscrow.sol";
import { GraphPayments } from "contracts/payments/GraphPayments.sol";
import { IGraphPayments } from "contracts/interfaces/IGraphPayments.sol";

import "./mocks/MockHorizonStaking.sol";
import "./mocks/MockGRTToken.sol";

contract GraphDeployments is Test {
    Controller public controller;
    MockGRTToken public token;
    GraphPayments public payments;
    GraphEscrow public escrow;
    MockHorizonStaking public staking;

    address public governor = address(0x4b39f53A1084b3eC5f2dA8f3B616D11317572efE);
    address public deployer = address(0x54705f06556182AeFfFe40386E85D3921c236f78);

    // GraphEscrow parameters

    uint256 public withdrawEscrowThawingPeriod = 60;

    // GraphPayments parameters

    uint256 public revokeCollectorThawingPeriod = 60;
    uint256 public protocolPaymentCut = 10000; // 1%

    // Staking parameters

    uint256 public delegationCut = 50000; // 5%

    // Setup

    constructor() {
        setUp();
    }

    function setUp() public {
        vm.prank(governor);
        controller = new Controller();

        // GraphPayments preddict address
        bytes32 saltPayments = keccak256("GraphPaymentsSalt");
        bytes32 paymentsHash = keccak256(bytes.concat(vm.getCode("GraphPayments.sol:GraphPayments"), abi.encode(address(controller), revokeCollectorThawingPeriod, protocolPaymentCut)));
        address predictedPaymentsAddress = vm.computeCreate2Address(saltPayments, paymentsHash, deployer);
        
        // GraphEscrow preddict address
        bytes32 saltEscrow = keccak256("GraphEscrowSalt");
        bytes32 escrowHash = keccak256(bytes.concat(vm.getCode("GraphEscrow.sol:GraphEscrow"), abi.encode(address(controller), withdrawEscrowThawingPeriod)));
        address predictedAddressEscrow = vm.computeCreate2Address(saltEscrow, escrowHash, deployer);

        // GraphToken
        vm.prank(deployer);
        token = new MockGRTToken();

        // HorizonStaking
        vm.prank(deployer);
        staking = new MockHorizonStaking(delegationCut);

        // Setup controller
        vm.startPrank(governor);
        controller.setContractProxy(keccak256("GraphToken"), address(token));
        controller.setContractProxy(keccak256("GraphEscrow"), predictedAddressEscrow);
        controller.setContractProxy(keccak256("GraphPayments"), predictedPaymentsAddress);
        controller.setContractProxy(keccak256("Staking"), address(staking));
        vm.stopPrank();
        
        vm.startPrank(deployer);
        payments = new GraphPayments{salt: saltPayments}(address(controller), revokeCollectorThawingPeriod, protocolPaymentCut);
        escrow = new GraphEscrow{salt: saltEscrow}(address(controller), withdrawEscrowThawingPeriod);
        vm.stopPrank();
    }

    // Tests

    function testDeployments() public view {
        assertEq(address(escrow.graphPayments()), address(payments));
        assertEq(address(payments.graphEscrow()), address(escrow));
    }
}