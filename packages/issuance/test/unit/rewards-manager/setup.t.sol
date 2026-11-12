// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerSetupTest is RewardsManagerSharedTest {
    function test_Setup_RewardsManagerWired() public view {
        assertEq(address(rm.subgraphService()), address(issuer));
        assertEq(rm.issuancePerBlock(), 200 ether);
    }
}
