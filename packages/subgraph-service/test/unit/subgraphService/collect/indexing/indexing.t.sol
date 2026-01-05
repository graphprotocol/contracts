// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../../SubgraphService.t.sol";
import { Allocation } from "../../../../../contracts/libraries/Allocation.sol";
contract SubgraphServiceCollectIndexingTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Collect_Indexing(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_WithDelegation(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 delegationFeeCut
    ) public useIndexer useAllocation(tokens) useDelegation(delegationTokens) {
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM);
        _setDelegationFeeCut(
            users.indexer,
            address(subgraphService),
            IGraphPayments.PaymentTypes.IndexingRewards,
            delegationFeeCut
        );

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_AfterUndelegate(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 delegationFeeCut
    ) public useIndexer useAllocation(tokens) useDelegation(delegationTokens) {
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM);
        _setDelegationFeeCut(
            users.indexer,
            address(subgraphService),
            IGraphPayments.PaymentTypes.IndexingRewards,
            delegationFeeCut
        );
        // Undelegate
        resetPrank(users.delegator);
        staking.undelegate(users.indexer, address(subgraphService), delegationTokens);

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        resetPrank(users.indexer);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_RewardsDestination(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) useRewardsDestination {
        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
        _collect(users.indexer, paymentType, data);
    }

    function test_subgraphService_Collect_Indexing_MultipleOverTime(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        uint8 numberOfPOIs = 20;
        uint256 timeBetweenPOIs = 5 days;

        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);

            resetPrank(users.indexer);

            bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }
    }

    function test_subgraphService_Collect_Indexing_MultipleOverTime_WithDelegation(
        uint256 tokens,
        uint256 delegationTokens,
        uint256 delegationFeeCut
    ) public useIndexer useAllocation(tokens) useDelegation(delegationTokens) {
        delegationFeeCut = bound(delegationFeeCut, 0, MAX_PPM);
        _setDelegationFeeCut(
            users.indexer,
            address(subgraphService),
            IGraphPayments.PaymentTypes.IndexingRewards,
            delegationFeeCut
        );

        uint8 numberOfPOIs = 20;
        uint256 timeBetweenPOIs = 5 days;
        for (uint8 i = 0; i < numberOfPOIs; i++) {
            // Skip forward
            skip(timeBetweenPOIs);

            resetPrank(users.indexer);

            bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }
    }

    function test_SubgraphService_Collect_Indexing_OverAllocated(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens * 2, 10_000_000_000 ether);

        // setup allocation
        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIDPrivateKey,
            tokens
        );
        _startService(users.indexer, data);

        // thaw some tokens to become over allocated
        staking.thaw(users.indexer, address(subgraphService), tokens / 2);

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // this collection should close the allocation
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory collectData = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());
        _collect(users.indexer, paymentType, collectData);
    }

    function test_SubgraphService_Collect_Indexing_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Attempt to collect from other indexer's allocation
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
                newIndexer,
                allocationID
            )
        );
        subgraphService.collect(newIndexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_ZeroRewards(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // Don't skip time - collect immediately, expecting zero rewards
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_ZeroPOI(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Submit zero POI (bytes32(0))
        bytes memory data = abi.encode(allocationID, bytes32(0), _getHardcodedPOIMetadata());

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Should succeed but reclaim rewards due to zero POI - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_StalePOI(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // Skip past maxPOIStaleness to make allocation stale
        skip(maxPOIStaleness + 1);

        // Should succeed but reclaim rewards due to stale POI - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_AltruisticAllocation(uint256 tokens) public useIndexer {
        tokens = bound(tokens, minimumProvisionTokens, MAX_TOKENS);

        _createProvision(users.indexer, tokens, fishermanRewardPercentage, disputePeriod);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Create altruistic allocation (0 tokens)
        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIDPrivateKey, 0);
        _startService(users.indexer, data);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory collectData = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Should succeed but reclaim rewards due to altruistic allocation - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, collectData);
    }

    function test_SubgraphService_Collect_Indexing_RevertWhen_AllocationClosed(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"), _getHardcodedPOIMetadata());

        // Close the allocation
        resetPrank(users.indexer);
        subgraphService.stopService(users.indexer, abi.encode(allocationID));

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Attempt to collect on closed allocation should revert
        // Using the bytes4 selector directly since AllocationManagerAllocationClosed is inherited from AllocationManager
        bytes4 selector = bytes4(keccak256("AllocationManagerAllocationClosed(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, allocationID));
        subgraphService.collect(users.indexer, paymentType, data);
    }
}
