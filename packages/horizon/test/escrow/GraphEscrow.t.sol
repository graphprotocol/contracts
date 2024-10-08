// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { HorizonStakingSharedTest } from "../shared/horizon-staking/HorizonStakingShared.t.sol";

contract GraphEscrowTest is HorizonStakingSharedTest {

    /*
     * MODIFIERS
     */

    modifier useGateway() {
        vm.startPrank(users.gateway);
        _;
        vm.stopPrank();
    }

    modifier approveEscrow(uint256 tokens) {
        _approveEscrow(tokens);
        _;
    }

    modifier useDeposit(uint256 tokens) {
        vm.assume(tokens > 0);
        vm.assume(tokens <= MAX_STAKING_TOKENS);
        _depositTokens(tokens);
        _;
    }

    modifier useCollector(uint256 tokens) {
        vm.assume(tokens > 0);
        escrow.approveCollector(users.verifier, tokens);
        _;
    }

    modifier depositAndThawTokens(uint256 amount, uint256 thawAmount) {
        vm.assume(thawAmount > 0);
        vm.assume(amount > thawAmount);
        _depositTokens(amount);
        escrow.thaw(users.verifier, users.indexer, thawAmount);
        _;
    }

    /*
     * HELPERS
     */

    function _depositTokens(uint256 tokens) internal {
        token.approve(address(escrow), tokens);
        escrow.deposit(users.verifier, users.indexer, tokens);
    }

    function _approveEscrow(uint256 tokens) internal {
        token.approve(address(escrow), tokens);
    }
}