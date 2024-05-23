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

    modifier approveEscrow(uint256 tokens) {
        changePrank(users.gateway);
        _approveEscrow(tokens);
        _;
    }

    modifier useDeposit(uint256 tokens) {
        changePrank(users.gateway);
        vm.assume(tokens > 0);
        vm.assume(tokens <= 10_000_000_000 ether);
        _depositTokens(tokens);
        _;
    }

    modifier useCollector(uint256 tokens) {
        changePrank(users.gateway);
        escrow.approveCollector(users.verifier, tokens);
        _;
    }

    function setUp() public virtual override {
        HorizonStakingSharedTest.setUp();
    }

    function _depositTokens(uint256 tokens) internal {
        token.approve(address(escrow), tokens);
        escrow.deposit(users.indexer, tokens);
    }

    function _approveEscrow(uint256 tokens) internal {
        token.approve(address(escrow), tokens);
    }
}