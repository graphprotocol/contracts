// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { L2CurationSharedTest } from "./L2CurationShared.t.sol";

contract ConservationTest is L2CurationSharedTest {
    function testFuzz_Conservation_DepositsAndRedeemsMatch(
        uint256[10] memory depositCuts,
        uint256[10] memory redeemCuts
    ) public {
        uint256 totalDeposits = 1_000_000_000 ether;

        // Signal multiple times
        uint256 totalSignal;
        uint256 remaining = totalDeposits;
        for (uint256 i = 0; i < 10; i++) {
            uint256 chunk = i == 9 ? remaining : bound(depositCuts[i], 0, remaining);
            remaining -= chunk;
            if (chunk == 0) continue;
            totalSignal += _mint(chunk);
        }
        assertEq(totalSignal, curation.getCuratorSignal(curator, SUBGRAPH_DEPLOYMENT_ID));

        // Redeem signal multiple times
        uint256 totalTokens;
        remaining = totalSignal;
        for (uint256 i = 0; i < 10; i++) {
            uint256 chunk = i == 9 ? remaining : bound(redeemCuts[i], 0, remaining);
            remaining -= chunk;
            if (chunk == 0) continue;
            vm.prank(curator);
            totalTokens += curation.burn(SUBGRAPH_DEPLOYMENT_ID, chunk, 0);
        }

        // Conservation of work
        (uint256 poolTokens, , ) = curation.pools(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(poolTokens, 0);
        assertEq(curation.getCurationPoolSignal(SUBGRAPH_DEPLOYMENT_ID), 0);
        assertFalse(curation.isCurated(SUBGRAPH_DEPLOYMENT_ID));
        assertEq(totalTokens, totalDeposits);
        assertEq(grt.balanceOf(curator), CURATOR_TOKENS);
        assertEq(grt.balanceOf(address(curation)), 0);
    }
}
