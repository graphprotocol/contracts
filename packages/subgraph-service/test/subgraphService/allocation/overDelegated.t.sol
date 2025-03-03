// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IHorizonStakingTypes } from "@graphprotocol/horizon/contracts/interfaces/internal/IHorizonStakingTypes.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
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
        uint256 indexerTokens = minimumProvisionTokens;
        uint256 allocationTokens = indexerTokens * delegationRatio;
        // Bound delegation tokens to be over delegated
        delegationTokens = bound(delegationTokens, allocationTokens, MAX_TOKENS);
        // Assume undelegation tokens to still leave indexer over delegated
        vm.assume(undelegationTokens > 1);
        vm.assume(undelegationTokens < delegationTokens - allocationTokens);

        // Create provision
        token.approve(address(staking), indexerTokens);
        _createProvision(users.indexer, indexerTokens, maxSlashingPercentage, disputePeriod);
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
            allocationIDPrivateKey,
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
