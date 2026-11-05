// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract CollectTest is L2CurationSharedTest {
    modifier curated() {
        _mint(1000 ether);
        _;
    }

    // -- > not curated --

    function test_NotCurated_RevertWhen_Collect() public {
        vm.expectRevert(bytes("Subgraph deployment must be curated to collect fees"));
        vm.prank(subgraphService);
        curation.collect(SUBGRAPH_DEPLOYMENT_ID, TOKENS_TO_COLLECT);
    }

    // -- > curated --

    function test_Curated_RevertWhen_CallerNotSubgraphService() public curated {
        vm.expectRevert(bytes("Caller must be the subgraph service"));
        vm.prank(me);
        curation.collect(SUBGRAPH_DEPLOYMENT_ID, TOKENS_TO_COLLECT);
    }

    function test_Curated_CollectTokens() public curated {
        _shouldCollect(1 ether);
        _shouldCollect(10 ether);
        _shouldCollect(100 ether);
        _shouldCollect(200 ether);
        _shouldCollect(500.25 ether);
    }

    function test_Curated_CollectThenBurnAll() public curated {
        // Collect increases the pool reserves
        _shouldCollect(100 ether);

        // When we burn signal we should get more tokens than initially curated
        uint256 signalToRedeem = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID);
        _shouldBurn(signalToRedeem, 1100 ether);
    }

    function test_Curated_CollectThenBurnMultipleTimes() public curated {
        uint256 tokensToCollect = 100 ether;
        _shouldCollect(tokensToCollect);

        // Burn partially
        uint256 signalOutRemainder = 1 ether;
        uint256 signalOutPartial = curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID) - signalOutRemainder;
        vm.prank(curator);
        uint256 tokensOut1 = curation.burn(SUBGRAPH_DEPLOYMENT_ID, signalOutPartial, 0);

        _shouldCollect(tokensToCollect);

        // Burn the rest
        vm.prank(curator);
        uint256 tokensOut2 = curation.burn(SUBGRAPH_DEPLOYMENT_ID, signalOutRemainder, 0);

        assertEq(tokensOut1 + tokensOut2, 1000 ether + tokensToCollect * 2);
    }
}
