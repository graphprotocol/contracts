// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

contract HorizonStakingAllocationTest is HorizonStakingTest {

    /*
     * TESTS
     */

    // function testAllocation_GetAllocation(uint256 tokens) public useIndexer useAllocation(tokens) {
    //     IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
    //     assertEq(allocation.indexer, _allocation.indexer);
    //     assertEq(allocation.subgraphDeploymentID, _allocation.subgraphDeploymentID);
    //     assertEq(allocation.tokens, _allocation.tokens);
    //     assertEq(allocation.createdAtEpoch, _allocation.createdAtEpoch);
    //     assertEq(allocation.closedAtEpoch, _allocation.closedAtEpoch);
    //     assertEq(allocation.collectedFees, _allocation.collectedFees);
    //     assertEq(allocation.__DEPRECATED_effectiveAllocation, _allocation.__DEPRECATED_effectiveAllocation);
    //     assertEq(allocation.accRewardsPerAllocatedToken, _allocation.accRewardsPerAllocatedToken);
    //     assertEq(allocation.distributedRebates, _allocation.distributedRebates);
    // }

    // function testAllocation_GetAllocationData(uint256 tokens) public useIndexer useAllocation(tokens) {
    //     (address indexer, bytes32 subgraphDeploymentID, uint256 tokens_, uint256 accRewardsPerAllocatedToken, uint256 accRewardsPending) = 
    //         staking.getAllocationData(_allocationId);
    //     assertEq(indexer, _allocation.indexer);
    //     assertEq(subgraphDeploymentID, _allocation.subgraphDeploymentID);
    //     assertEq(tokens_, _allocation.tokens);
    //     assertEq(accRewardsPerAllocatedToken, _allocation.accRewardsPerAllocatedToken);
    //     assertEq(accRewardsPending, 0);
    // }

    function testAllocation_GetAllocationState_Active(uint256 tokens) public useIndexer useAllocation(tokens) {
        IHorizonStakingExtension.AllocationState state = staking.getAllocationState(_allocationId);
        assertEq(uint16(state), uint16(IHorizonStakingExtension.AllocationState.Active));
    }

    function testAllocation_GetAllocationState_Null() public view {
        IHorizonStakingExtension.AllocationState state = staking.getAllocationState(_allocationId);
        assertEq(uint16(state), uint16(IHorizonStakingExtension.AllocationState.Null));
    }

    function testAllocation_IsAllocation(uint256 tokens) public useIndexer useAllocation(tokens) {
        bool isAllocation = staking.isAllocation(_allocationId);
        assertTrue(isAllocation);
    }

    function testAllocation_IsNotAllocation() public view {
        bool isAllocation = staking.isAllocation(_allocationId);
        assertFalse(isAllocation);
    }
}