// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocationForceCloseTest is SubgraphServiceTest {
    address private permissionlessBob = makeAddr("permissionlessBob");

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_ForceClose_Stale(uint256 tokens) public useIndexer useAllocation(tokens) {
        // Skip forward
        skip(maxPOIStaleness + 1);

        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_ForceClose_Stale_AfterCollecting(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Simulate POIs being submitted
        uint8 numberOfPOIs = 5;
        uint256 timeBetweenPOIs = 5 days;

        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);

            bytes memory data = abi.encode(allocationID, bytes32("POI1"), _getHardcodedPOIMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }

        // Skip forward so that the allocation is stale
        skip(maxPOIStaleness + 1);

        // Close the stale allocation
        resetPrank(permissionlessBob);
        _closeStaleAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_NotStale(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        // Simulate POIs being submitted
        uint8 numberOfPOIs = 20;
        uint256 timeBetweenPOIs = (maxPOIStaleness - 1) / numberOfPOIs;

        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);

            resetPrank(users.indexer);

            bytes memory data = abi.encode(allocationID, bytes32("POI1"), _getHardcodedPOIMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);

            resetPrank(permissionlessBob);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISubgraphService.SubgraphServiceCannotForceCloseAllocation.selector,
                    allocationID
                )
            );
            subgraphService.closeStaleAllocation(allocationID);
        }
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_Altruistic(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIDPrivateKey, 0);
        _startService(users.indexer, data);

        skip(maxPOIStaleness + 1);

        resetPrank(permissionlessBob);
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceAllocationIsAltruistic.selector, allocationID)
        );
        subgraphService.closeStaleAllocation(allocationID);
    }

    function test_SubgraphService_Allocation_ForceClose_RevertIf_Paused() public useIndexer useAllocation(1000 ether) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(permissionlessBob);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        subgraphService.closeStaleAllocation(allocationID);
    }
}
