// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationOverDelegatedTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_OverDelegated_NotOverAllocatedAfterUndelegation(
        uint256 delegationTokens,
        uint256 undelegationTokens
    ) public useIndexer {
        // Use minimum provision tokens
        uint256 indexerTokens = MINIMUM_PROVISION_TOKENS;
        uint256 allocationTokens = indexerTokens * DELEGATION_RATIO;
        // Bound delegation tokens to be over delegated
        delegationTokens = bound(delegationTokens, allocationTokens, MAX_TOKENS);
        // Assume undelegation tokens to still leave indexer over delegated
        vm.assume(undelegationTokens > 1);
        vm.assume(undelegationTokens < delegationTokens - allocationTokens);

        // Create provision
        token.approve(address(staking), indexerTokens);
        _createProvision(users.indexer, indexerTokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Delegate so that indexer is over allocated
        resetPrank(users.delegator);
        token.approve(address(staking), delegationTokens);
        _delegate(users.indexer, address(subgraphService), delegationTokens, 0);

        // Create allocation
        resetPrank(users.indexer);
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIdPrivateKey,
            allocationTokens
        );
        _startService(users.indexer, data);

        // Undelegate
        resetPrank(users.delegator);
        _undelegate(users.indexer, address(subgraphService), undelegationTokens);

        // Check that indexer is not over allocated
        assertFalse(subgraphService.isOverAllocated(users.indexer));
    }
}
