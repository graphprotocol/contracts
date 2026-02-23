// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAllocationManager } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../../SubgraphService.t.sol";
contract SubgraphServiceCollectIndexingTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Collect_Indexing(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

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
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
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
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_RewardsDestination(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) useRewardsDestination {
        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
        _collect(users.indexer, paymentType, data);
    }

    function test_subgraphService_Collect_Indexing_MultipleOverTime(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        uint8 numberOfPoIs = 20;
        uint256 timeBetweenPoIs = 5 days;

        for (uint8 i = 0; i < numberOfPoIs; i++) {
            // Skip forward
            skip(timeBetweenPoIs);

            resetPrank(users.indexer);

            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
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

        uint8 numberOfPoIs = 20;
        uint256 timeBetweenPoIs = 5 days;
        for (uint8 i = 0; i < numberOfPoIs; i++) {
            // Skip forward
            skip(timeBetweenPoIs);

            resetPrank(users.indexer);

            // forge-lint: disable-next-line(unsafe-typecast)
            bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
            _collect(users.indexer, IGraphPayments.PaymentTypes.IndexingRewards, data);
        }
    }

    function test_SubgraphService_Collect_Indexing_OverAllocated(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS * 2, 10_000_000_000 ether);

        // setup allocation
        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            users.indexer,
            subgraphDeployment,
            allocationIdPrivateKey,
            tokens
        );
        _startService(users.indexer, data);

        // thaw some tokens to become over allocated
        staking.thaw(users.indexer, address(subgraphService), tokens / 2);

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // this collection should close the allocation
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory collectData = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());
        _collect(users.indexer, paymentType, collectData);
    }

    function test_SubgraphService_Collect_Indexing_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Attempt to collect from other indexer's allocation
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
                newIndexer,
                allocationId
            )
        );
        subgraphService.collect(newIndexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_ZeroRewards(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // Don't skip time - collect immediately, expecting zero rewards
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_ZeroPOI(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Submit zero POI (bytes32(0))
        bytes memory data = abi.encode(allocationId, bytes32(0), _getHardcodedPoiMetadata());

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Should succeed but reclaim rewards due to zero POI - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_StalePOI(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // Skip past MAX_POI_STALENESS to make allocation stale
        skip(MAX_POI_STALENESS + 1);

        // Should succeed but reclaim rewards due to stale POI - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_DeniedSubgraph(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // skip time to ensure allocation is not too young (isDenied is only checked after epoch check)
        vm.roll(block.number + EPOCH_LENGTH);

        // Mock the rewards manager to deny this subgraph deployment
        vm.mockCall(
            address(rewardsManager),
            abi.encodeWithSelector(IRewardsManager.isDenied.selector, subgraphDeployment),
            abi.encode(true)
        );

        // Should succeed but return zero rewards due to denied subgraph
        subgraphService.collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_AltruisticAllocation(uint256 tokens) public useIndexer {
        tokens = bound(tokens, MINIMUM_PROVISION_TOKENS, MAX_TOKENS);

        _createProvision(users.indexer, tokens, FISHERMAN_REWARD_PERCENTAGE, DISPUTE_PERIOD);
        _register(users.indexer, abi.encode("url", "geoHash", address(0)));

        // Create altruistic allocation (0 tokens)
        bytes memory data = _createSubgraphAllocationData(users.indexer, subgraphDeployment, allocationIdPrivateKey, 0);
        _startService(users.indexer, data);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory collectData = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Should succeed but reclaim rewards due to altruistic allocation - just verify it doesn't revert
        subgraphService.collect(users.indexer, paymentType, collectData);
    }

    function test_SubgraphService_Collect_Indexing_RevertWhen_AllocationClosed(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI"), _getHardcodedPoiMetadata());

        // Close the allocation
        resetPrank(users.indexer);
        subgraphService.stopService(users.indexer, abi.encode(allocationId));

        // skip time to ensure allocation could get rewards
        vm.roll(block.number + EPOCH_LENGTH);

        // Attempt to collect on closed allocation should revert
        vm.expectRevert(
            abi.encodeWithSelector(IAllocationManager.AllocationManagerAllocationClosed.selector, allocationId)
        );
        subgraphService.collect(users.indexer, paymentType, data);
    }
}
