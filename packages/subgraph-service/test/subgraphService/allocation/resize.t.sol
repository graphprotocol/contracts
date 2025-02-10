// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

contract SubgraphServiceAllocationResizeTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function test_SubgraphService_Allocation_Resize(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationID, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_AfterCollectingIndexingRewards(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingRewards;
        bytes memory data = abi.encode(allocationID, bytes32("POI1"));
        _collect(users.indexer, paymentType, data);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationID, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_SecondTime(uint256 tokens, uint256 firstResizeTokens, uint256 secondResizeTokens) public useIndexer useAllocation(tokens) {
        firstResizeTokens = bound(firstResizeTokens, 1, MAX_TOKENS);
        secondResizeTokens = bound(secondResizeTokens, 1, MAX_TOKENS);
        vm.assume(firstResizeTokens != tokens);
        vm.assume(secondResizeTokens != firstResizeTokens);

        mint(users.indexer, firstResizeTokens);
        _addToProvision(users.indexer, firstResizeTokens);
        _resizeAllocation(users.indexer, allocationID, firstResizeTokens);

        mint(users.indexer, secondResizeTokens);
        _addToProvision(users.indexer, secondResizeTokens);
        _resizeAllocation(users.indexer, allocationID, secondResizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertWhen_NotAuthorized(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);

        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            newIndexer,
            allocationID
        ));
        subgraphService.resizeAllocation(newIndexer, allocationID, resizeTokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertWhen_SameSize(uint256 tokens) public useIndexer useAllocation(tokens) {
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationSameSize.selector,
            allocationID,
            tokens
        ));
        subgraphService.resizeAllocation(users.indexer, allocationID, tokens);
    }

    function test_SubgraphService_Allocation_Resize_RevertIf_AllocationIsClosed(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);
        bytes memory data = abi.encode(allocationID);
        _stopService(users.indexer, data);
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationClosed.selector,
            allocationID
        ));
        subgraphService.resizeAllocation(users.indexer, allocationID, resizeTokens);
    }
}
