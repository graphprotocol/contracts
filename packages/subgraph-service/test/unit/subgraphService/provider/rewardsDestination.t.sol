// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceProviderRewardsDestinationTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Provider_RewardsDestination_Set(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Should be able to use new address
        _setRewardsDestination(users.rewardsDestination);

        // Should be able to set back to address zero
        _setRewardsDestination(address(0));
    }
}
