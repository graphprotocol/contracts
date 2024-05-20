// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStaking.t.sol";

contract GraphEscrowTest is HorizonStakingSharedTest {

    modifier useGateway() {
        vm.startPrank(users.gateway);
        _;
        vm.stopPrank();
    }

    modifier approveEscrow(uint256 amount) {
        _approveEscrow(amount);
        _;
    }

    modifier depositTokens(uint256 amount) {
        vm.assume(amount > 0);
        vm.assume(amount <= 10000 ether);
        _depositTokens(amount);
        _;
    }

    function setUp() public virtual override {
        HorizonStakingSharedTest.setUp();
    }

    function _depositTokens(uint256 amount) internal {
        token.approve(address(escrow), amount);
        escrow.deposit(users.indexer, amount);
    }

    function _approveEscrow(uint256 amount) internal {
        token.approve(address(escrow), amount);
    }
}