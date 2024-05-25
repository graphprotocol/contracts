// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { GraphBaseTest } from "../../GraphBase.t.sol";

abstract contract HorizonStakingSharedTest is GraphBaseTest {

    modifier useIndexer() {
        vm.startPrank(users.indexer);
        _;
        vm.stopPrank();
    }

    modifier assumeProvisionTokens(uint256 tokens) {
        vm.assume(tokens > MIN_PROVISION_SIZE);
        vm.assume(tokens <= 10_000_000_000 ether);
        _;
    }

    modifier useProvision(uint256 tokens, uint32 maxVerifierCut, uint64 thawingPeriod) {
        vm.assume(tokens <= 10_000_000_000 ether);
        vm.assume(tokens > MIN_PROVISION_SIZE);
        vm.assume(maxVerifierCut <= MAX_MAX_VERIFIER_CUT);
        vm.assume(thawingPeriod <= MAX_THAWING_PERIOD);
        _createProvision(subgraphDataServiceAddress, tokens, maxVerifierCut, thawingPeriod);
        _;
    }

    modifier useDelegationFeeCut(uint256 paymentType, uint256 cut) {
        _setDelegationFeeCut(paymentType, cut);
        _;
    }

    /* Set Up */

    function setUp() public virtual override {
        GraphBaseTest.setUp();  
    }

    /* Helpers */

    function _createProvision(
        address dataServiceAddress,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) internal {
        token.approve(address(staking), tokens);
        staking.stakeTo(users.indexer, tokens);
        staking.provision(
            users.indexer,
            dataServiceAddress,
            tokens,
            maxVerifierCut,
            thawingPeriod
        );
    }

    function _setDelegationFeeCut(uint256 paymentType, uint256 cut) internal {
        staking.setDelegationFeeCut(users.indexer, subgraphDataServiceAddress, paymentType, cut);
    }
}
