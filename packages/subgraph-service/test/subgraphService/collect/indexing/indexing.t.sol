// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { ISubgraphService } from "../../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../../SubgraphService.t.sol";
import { Allocation } from "../../../../contracts/libraries/Allocation.sol";
contract SubgraphServiceCollectIndexingTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Collect_Indexing(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"));

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
        bytes memory data = abi.encode(allocationID, bytes32("POI"));
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
        bytes memory data = abi.encode(allocationID, bytes32("POI"));
        _collect(users.indexer, paymentType, data);
    }

    function test_SubgraphService_Collect_Indexing_RewardsDestination(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) useRewardsDestination {
        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI"));
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

            bytes memory data = abi.encode(allocationID, bytes32("POI"));
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

            bytes memory data = abi.encode(allocationID, bytes32("POI"));
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
        bytes memory collectData = abi.encode(allocationID, bytes32("POI"));
        _collect(users.indexer, paymentType, collectData);
    }

    function test_SubgraphService_Collect_Indexing_RevertWhen_IndexerIsNotAllocationOwner(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // Setup new indexer
        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        bytes memory data = abi.encode(allocationID, bytes32("POI"));

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
}
