// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { Controller } from "@graphprotocol/contracts/contracts/governance/Controller.sol";
import { PaymentsEscrow } from "contracts/payments/PaymentsEscrow.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

contract GraphEscrowConstructorTest is Test {
    Controller public controller;

    function setUp() public {
        controller = new Controller();

        // GraphDirectory requires all proxy contracts to be registered
        controller.setContractProxy(keccak256("GraphToken"), makeAddr("GraphToken"));
        controller.setContractProxy(keccak256("Staking"), makeAddr("Staking"));
        controller.setContractProxy(keccak256("GraphPayments"), makeAddr("GraphPayments"));
        controller.setContractProxy(keccak256("PaymentsEscrow"), makeAddr("PaymentsEscrow"));
        controller.setContractProxy(keccak256("EpochManager"), makeAddr("EpochManager"));
        controller.setContractProxy(keccak256("RewardsManager"), makeAddr("RewardsManager"));
        controller.setContractProxy(keccak256("GraphTokenGateway"), makeAddr("GraphTokenGateway"));
        controller.setContractProxy(keccak256("GraphProxyAdmin"), makeAddr("GraphProxyAdmin"));
    }

    function testConstructor_MaxWaitPeriodBoundary() public {
        uint256 maxWaitPeriod = 90 days;

        // Exactly at MAX_WAIT_PERIOD should succeed
        PaymentsEscrow escrowAtMax = new PaymentsEscrow(address(controller), maxWaitPeriod);
        assertEq(escrowAtMax.WITHDRAW_ESCROW_THAWING_PERIOD(), maxWaitPeriod);
    }

    function testConstructor_RevertWhen_ThawingPeriodTooLong() public {
        uint256 maxWaitPeriod = 90 days;
        uint256 tooLong = maxWaitPeriod + 1;

        vm.expectRevert(
            abi.encodeWithSelector(IPaymentsEscrow.PaymentsEscrowThawingPeriodTooLong.selector, tooLong, maxWaitPeriod)
        );
        new PaymentsEscrow(address(controller), tooLong);
    }

    function testConstructor_ZeroThawingPeriod() public {
        PaymentsEscrow escrowZero = new PaymentsEscrow(address(controller), 0);
        assertEq(escrowZero.WITHDRAW_ESCROW_THAWING_PERIOD(), 0);
    }
}
