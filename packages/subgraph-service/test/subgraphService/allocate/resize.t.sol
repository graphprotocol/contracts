// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceAllocateResizeTest is SubgraphServiceTest {

    /*
     * Helpers
     */

    function _setupResize(address _indexer, uint256 _tokens) private {
        
        token.approve(address(staking), _tokens);
        staking.stakeTo(_indexer, _tokens);
        staking.addToProvision(_indexer, address(subgraphService), _tokens);
    }

    function _resizeAllocation(address _indexer, address _allocationID, bytes32 _subgraphDeployment, uint256 _tokens) private {
        uint256 oldAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(_subgraphDeployment);
        vm.expectEmit(address(subgraphService));
        emit AllocationManager.AllocationResized(_indexer, _allocationID, _subgraphDeployment, _tokens, oldAllocatedTokens);
        subgraphService.resizeAllocation(_indexer, _allocationID, _tokens);

        Allocation.State memory allocation = subgraphService.getAllocation(_allocationID);
        assertEq(allocation.tokens, _tokens);
        assertEq(allocation.accRewardsPerAllocatedToken, rewardsPerSubgraphAllocationUpdate);

        uint256 subgraphAllocatedTokens = subgraphService.getSubgraphAllocatedTokens(_subgraphDeployment);
        assertEq(subgraphAllocatedTokens, _tokens);
    }

    /*
     * TESTS
     */

    function testResize_Allocation(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationID, subgraphDeployment, resizeTokens);
    }

    function testResize_Allocation_AfterCollectingIndexingRewards(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, 1, MAX_TOKENS);
        vm.assume(resizeTokens != tokens);

        mint(users.indexer, resizeTokens);
        _collectIndexingRewards(users.indexer, allocationID, tokens);
        _addToProvision(users.indexer, resizeTokens);
        _resizeAllocation(users.indexer, allocationID, subgraphDeployment, resizeTokens);
    }

    function testResize_Allocation_SecondTime(uint256 tokens, uint256 firstResizeTokens, uint256 secondResizeTokens) public useIndexer useAllocation(tokens) {
        firstResizeTokens = bound(firstResizeTokens, 1, MAX_TOKENS);
        secondResizeTokens = bound(secondResizeTokens, 1, MAX_TOKENS);
        vm.assume(firstResizeTokens != tokens);
        vm.assume(secondResizeTokens != firstResizeTokens);

        mint(users.indexer, firstResizeTokens);
        _addToProvision(users.indexer, firstResizeTokens);
        _resizeAllocation(users.indexer, allocationID, subgraphDeployment, firstResizeTokens);

        mint(users.indexer, secondResizeTokens);
        _addToProvision(users.indexer, secondResizeTokens);
        _resizeAllocation(users.indexer, allocationID, subgraphDeployment, secondResizeTokens);
    }

    function testResize_RevertWhen_NotAuthorized(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);

        address newIndexer = makeAddr("newIndexer");
        _createAndStartAllocation(newIndexer, tokens);
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerNotAuthorized.selector,
            newIndexer,
            allocationID
        ));
        subgraphService.resizeAllocation(newIndexer, allocationID, resizeTokens);
    }

    function testResize_RevertWhen_SameSize(uint256 tokens) public useIndexer useAllocation(tokens) {
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationSameSize.selector,
            allocationID,
            tokens
        ));
        subgraphService.resizeAllocation(users.indexer, allocationID, tokens);
    }

    function testResize_RevertIf_AllocationIsClosed(uint256 tokens, uint256 resizeTokens) public useIndexer useAllocation(tokens) {
        resizeTokens = bound(resizeTokens, tokens + 1, MAX_TOKENS);
        _stopAllocation(users.indexer, allocationID);
        vm.expectRevert(abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationClosed.selector,
            allocationID
        ));
        subgraphService.resizeAllocation(users.indexer, allocationID, resizeTokens);
    }
}
