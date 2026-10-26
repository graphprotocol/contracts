// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DiscoveryTest } from "../shared/DiscoveryTest.t.sol";
import { IL2CurationLike } from "../interfaces/IL2CurationLike.sol";

abstract contract L2CurationSharedTest is DiscoveryTest {
    uint32 internal constant MAX_PPM = 1_000_000;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID = keccak256("subgraphDeploymentID");
    uint256 internal constant SIGNAL_AMOUNT_FOR_1000_TOKENS = 1000 ether;
    uint256 internal constant SIGNAL_AMOUNT_FOR_MINIMUM_CURATION = 1;
    uint256 internal constant CURATOR_TOKENS = 1_000_000_000 ether;
    uint256 internal constant TOKENS_TO_DEPOSIT = 1000 ether;
    uint256 internal constant TOKENS_TO_COLLECT = 2000 ether;

    struct State {
        uint256 tokenTotalSupply;
        uint256 curatorTokens;
        uint256 curatorSignal;
        uint256 poolTokens;
        uint256 poolSignal;
        uint256 totalTokens;
    }

    function setUp() public virtual override {
        super.setUp();

        // Curator and GNS funds (GNS already approved curation in approveAll)
        vm.startPrank(governor);
        grt.mint(curator, CURATOR_TOKENS);
        grt.mint(address(gns), CURATOR_TOKENS);
        grt.mint(subgraphService, TOKENS_TO_COLLECT);
        vm.stopPrank();
        vm.prank(curator);
        grt.approve(address(curation), CURATOR_TOKENS);
        vm.prank(subgraphService);
        grt.approve(address(curation), TOKENS_TO_COLLECT);
    }

    function _state(address account) internal view returns (State memory s) {
        s.tokenTotalSupply = grt.totalSupply();
        s.curatorTokens = grt.balanceOf(account);
        s.curatorSignal = curation.getCuratorSignal(account, SUBGRAPH_DEPLOYMENT_ID);
        (s.poolTokens, , ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        s.poolSignal = curation.getCurationPoolSignal(SUBGRAPH_DEPLOYMENT_ID);
        s.totalTokens = grt.balanceOf(address(curation));
    }

    function _shouldMint(uint256 tokensToDeposit, uint256 expectedSignal) internal {
        State memory before = _state(curator);
        uint256 curationTax = (tokensToDeposit * curation.curationTaxPercentage()) / MAX_PPM;

        vm.expectEmit(address(curation));
        emit IL2CurationLike.Signalled(curator, SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, expectedSignal, curationTax);
        vm.prank(curator);
        curation.mint(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, 0);

        State memory afterState = _state(curator);
        (, uint32 reserveRatio, ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterState.curatorTokens, before.curatorTokens - tokensToDeposit);
        assertEq(afterState.curatorSignal, before.curatorSignal + expectedSignal);
        assertEq(afterState.poolTokens, before.poolTokens + tokensToDeposit - curationTax);
        assertEq(afterState.poolSignal, before.poolSignal + expectedSignal);
        // Pool reserveRatio is deprecated and therefore always zero in L2
        assertEq(reserveRatio, 0);
        assertEq(afterState.totalTokens, before.totalTokens + tokensToDeposit - curationTax);
        // Total supply is reduced by the curation tax burn
        assertEq(afterState.tokenTotalSupply, before.tokenTotalSupply - curationTax);
    }

    function _shouldMintTaxFree(uint256 tokensToDeposit, uint256 expectedSignal) internal {
        State memory before = _state(address(gns));

        vm.expectEmit(address(curation));
        emit IL2CurationLike.Signalled(address(gns), SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit, expectedSignal, 0);
        vm.prank(address(gns));
        curation.mintTaxFree(SUBGRAPH_DEPLOYMENT_ID, tokensToDeposit);

        State memory afterState = _state(address(gns));
        (, uint32 reserveRatio, ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterState.curatorTokens, before.curatorTokens - tokensToDeposit);
        assertEq(afterState.curatorSignal, before.curatorSignal + expectedSignal);
        assertEq(afterState.poolTokens, before.poolTokens + tokensToDeposit);
        assertEq(afterState.poolSignal, before.poolSignal + expectedSignal);
        assertEq(reserveRatio, 0);
        assertEq(afterState.totalTokens, before.totalTokens + tokensToDeposit);
        assertEq(afterState.tokenTotalSupply, before.tokenTotalSupply);
    }

    function _shouldBurn(uint256 signalToRedeem, uint256 expectedTokens) internal {
        State memory before = _state(curator);

        vm.expectEmit(address(curation));
        emit IL2CurationLike.Burned(curator, SUBGRAPH_DEPLOYMENT_ID, expectedTokens, signalToRedeem);
        vm.prank(curator);
        curation.burn(SUBGRAPH_DEPLOYMENT_ID, signalToRedeem, 0);

        State memory afterState = _state(curator);
        assertEq(afterState.curatorTokens, before.curatorTokens + expectedTokens);
        assertEq(afterState.curatorSignal, before.curatorSignal - signalToRedeem);
        assertEq(afterState.poolTokens, before.poolTokens - expectedTokens);
        assertEq(afterState.poolSignal, before.poolSignal - signalToRedeem);
        assertEq(afterState.totalTokens, before.totalTokens - expectedTokens);
        // Total supply is conserved
        assertEq(afterState.tokenTotalSupply, before.tokenTotalSupply);
    }

    function _shouldCollect(uint256 tokensToCollect) internal {
        (uint256 beforePoolTokens, , ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        uint256 beforeTotalBalance = grt.balanceOf(address(curation));

        vm.prank(subgraphService);
        grt.transfer(address(curation), tokensToCollect);
        vm.expectEmit(address(curation));
        emit IL2CurationLike.Collected(SUBGRAPH_DEPLOYMENT_ID, tokensToCollect);
        vm.prank(subgraphService);
        curation.collect(SUBGRAPH_DEPLOYMENT_ID, tokensToCollect);

        (uint256 afterPoolTokens, , ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterPoolTokens, beforePoolTokens + tokensToCollect);
        assertEq(grt.balanceOf(address(curation)), beforeTotalBalance + tokensToCollect);
    }

    function _mint(uint256 tokens) internal returns (uint256 signal) {
        vm.prank(curator);
        (signal, ) = curation.mint(SUBGRAPH_DEPLOYMENT_ID, tokens, 0);
    }
}
