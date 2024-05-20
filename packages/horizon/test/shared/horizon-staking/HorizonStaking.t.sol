// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {

    /* Set Up */

    function setUp() public virtual override {
        GraphBaseTest.setUp();  
    }

    /* Helpers */

    function createProvision(uint256 tokens) internal {
        vm.startPrank(users.indexer);
        token.approve(address(staking), tokens);
        staking.stakeTo(users.indexer, tokens);
        staking.provision(users.indexer, subgraphDataServiceAddress, tokens, 0, 0);
    }

    function setDelegationFeeCut(uint256 paymentType, uint256 cut) internal {
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
    }
}
