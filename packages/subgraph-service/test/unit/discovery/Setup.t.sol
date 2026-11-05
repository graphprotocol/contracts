// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GNSHelpers } from "./shared/GNSHelpers.t.sol";

contract SetupTest is GNSHelpers {
    function test_Setup_Wired() public view {
        assertEq(nft.minter(), address(gns));
        assertEq(curation.subgraphService(), subgraphService);
        assertEq(gns.counterpartGNSAddress(), l1GNS);
    }

    function test_Setup_PublishNewSubgraph() public {
        _publishNewSubgraph(me, DEPLOYMENT_ID_0);
    }
}
