// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationForceCloseTest is SubgraphServiceTest {
    address private permissionlessBob = makeAddr("permissionlessBob");

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_ForceClose_Stale(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Skip forward
        skip(MAX_POI_STALENESS + 1);

        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationId);
    }

    function test_SubgraphService_Allocation_ForceClose_Stale_AfterCollecting(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Simulate POIs being submitted
        uint8 numberOfPoIs = 5;
        uint256 timeBetweenPoIs = 5 days;

        for (uint8 i = 0; i < numberOfPoIs; i++) {
            // Skip forward
            skip(timeBetweenPoIs);

            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory data = abi.encode(allocationId, bytes32("POI1"), _getHardcodedPoiMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }

        // Skip forward so that the allocation is stale
        skip(MAX_POI_STALENESS + 1);

        // Close the stale allocation
        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationId);
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_NotStale(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Simulate POIs being submitted
        uint8 numberOfPoIs = 20;
        uint256 timeBetweenPoIs = (MAX_POI_STALENESS - 1) / numberOfPoIs;

        for (uint8 i = 0; i < numberOfPoIs; i++) {
            // Skip forward
            skip(timeBetweenPoIs);

            resetPrank(users.indexer);

            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory data = abi.encode(allocationId, bytes32("POI1"), _getHardcodedPoiMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);

            resetPrank(permissionlessBob);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISubgraphService.SubgraphServiceCannotForceCloseAllocation.selector,
                    allocationId
                )
            );
            subgraphService.closeStaleAllocation(allocationId);
        }
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_Altruistic(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);

        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIdPrivateKey, 0);
        _startService(users.indexer, data);

        skip(MAX_POI_STALENESS + 1);

        resetPrank(permissionlessBob);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceAllocationIsAltruistic.selector, allocationId)
        );
        subgraphService.closeStaleAllocation(allocationId);
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_Paused() public useIndexer useAllocation(1000 ether) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(permissionlessBob);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        subgraphService.closeStaleAllocation(allocationId);
    }
}
