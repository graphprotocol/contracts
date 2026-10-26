// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { DiscoveryTest } from "./shared/DiscoveryTest.t.sol";

contract SetupTest is DiscoveryTest {
    function test_Setup_Wired() public view {
        assertEq(nft.minter(), address(gns));
        assertEq(curation.subgraphService(), subgraphService);
        assertEq(gns.counterpartGNSAddress(), l1GNS);
    }
}
