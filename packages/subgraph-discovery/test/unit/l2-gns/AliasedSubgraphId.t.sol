// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "../shared/GNSHelpers.t.sol";

contract AliasedSubgraphIdTest is GNSHelpers {
    uint256 internal constant OFFSET = 0x1111000000000000000000000000000000000000000000000000000000001111;

    // -- getAliasedL2SubgraphID --

    function test_GetAliasedL2SubgraphID_AddsOffset() public view {
        uint256 l1SubgraphId = 68799548758199140224151701590582019137924969401915573086349306511960790045480;
        uint256 expectedL2SubgraphId;
        unchecked {
            expectedL2SubgraphId = l1SubgraphId + OFFSET;
        }
        assertEq(gns.getAliasedL2SubgraphID(l1SubgraphId), expectedL2SubgraphId);
    }

    function test_GetAliasedL2SubgraphID_WrapsAroundMaxUint256() public view {
        uint256 l1SubgraphId = type(uint256).max;
        uint256 expectedL2SubgraphId;
        unchecked {
            expectedL2SubgraphId = l1SubgraphId + OFFSET;
        }
        assertEq(gns.getAliasedL2SubgraphID(l1SubgraphId), expectedL2SubgraphId);
        assertEq(expectedL2SubgraphId, OFFSET - 1);
    }
}
