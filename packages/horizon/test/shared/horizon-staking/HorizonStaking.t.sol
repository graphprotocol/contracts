// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {

    modifier useProvision(uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) {
        vm.assume(tokens <= 10_000_000_000 ether);
        vm.assume(tokens > 1e18);
        _createProvision(tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) {
        _setDelegationFeeCut(paymentType, cut);
        _;
    }

    /* Set Up */

    function setUp() public virtual override {
        GraphBaseTest.setUp();  
    }

    /* Helpers */

    function _createProvision(uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) internal {
        vm.startPrank(users.indexer);
        token.approve(address(staking), tokens);
        staking.stakeTo(users.indexer, tokens);
        staking.provision(
            users.indexer,
            subgraphDataServiceAddress,
            tokens,
            maxVerifierCut,
            thawingPeriod
        );
        vm.stopPrank();
    }

    function _setDelegationFeeCut(IGraphPayments.PaymentTypes paymentType, uint256 cut) internal {
        vm.prank(users.indexer);
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
    }
}
