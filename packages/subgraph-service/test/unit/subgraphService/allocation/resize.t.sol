// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { IAllocationManager } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocationManager.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

contract SubgraphServiceAllocationResizeTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_Resize(
        uint256 tokens,
        uint256 resizeTokens
    ) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationId, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_AfterCollectingIndexingRewards(
        uint256 tokens,
        uint256 resizeTokens
    ) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);

        // skip time to ensure allocation gets rewards
        vm.roll(block.number + EPOCH_LENGTH);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory data = abi.encode(allocationId, bytes32("POI1"), _getHardcodedPoiMetadata());
        _collect(users.indexer, paymentType, data);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationId, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_SecondTime(
        uint256 tokens,
        uint256 firstResizeTokens,
        uint256 secondResizeTokens
    ) public useIndexer useAllocation(tokens) {
        firstResizeTokens = bound(firstResizeTokens, 1, MAX_TOKENS);
        secondResizeTokens = bound(secondResizeTokens, 1, MAX_TOKENS);
        vm.assume(firstResizeTokens != tokens);
        vm.assume(secondResizeTokens != firstResizeTokens);

        mint(users.indexer, firstResizeTokens);
        _addToProvision(users.indexer, firstResizeTokens);
        _resizeAllocation(users.indexer, allocationId, firstResizeTokens);

        mint(users.indexer, secondResizeTokens);
        _addToProvision(users.indexer, secondResizeTokens);
        _resizeAllocation(users.indexer, allocationId, secondResizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertWhen_NotAuthorized(
        uint256 tokens,
        uint256 resizeTokens
    ) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);

        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
                newIndexer,
                allocationId
            )
        );
        subgraphService.resizeAllocation(newIndexer, allocationId, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertWhen_SameSize(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAllocationManager.AllocationManagerAllocationSameSize.selector,
                allocationId,
                tokens
            )
        );
        subgraphService.resizeAllocation(users.indexer, allocationId, tokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertIf_AllocationIsClosed(
        uint256 tokens,
        uint256 resizeTokens
    ) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);
        bytes memory data = abi.encode(allocationId);
        _stopService(users.indexer, data);
        vm.expectRevert(
            abi.encodeWithSelector(IAllocationManager.AllocationManagerAllocationClosed.selector, allocationId)
        );
        subgraphService.resizeAllocation(users.indexer, allocationId, resizeTokens);
    }
}
