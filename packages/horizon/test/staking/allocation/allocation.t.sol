// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingExtensionTest } from "./HorizonStakingExtension.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

contract HorizonStakingAllocationTest is HorizonStakingExtensionTest {

    /*
     * TESTS
     */

    function testAllocation_GetAllocation() public useAllocation {
        IHorizonStakingExtension.Allocation memory allocation = staking.getAllocation(_allocationId);
        assertEq(allocation.indexer, _allocation.indexer);
        assertEq(allocation.subgraphDeploymentID, _allocation.subgraphDeploymentID);
        assertEq(allocation.tokens, _allocation.tokens);
        assertEq(allocation.createdAtEpoch, _allocation.createdAtEpoch);
        assertEq(allocation.closedAtEpoch, _allocation.closedAtEpoch);
        assertEq(allocation.collectedFees, _allocation.collectedFees);
        assertEq(allocation.__DEPRECATED_effectiveAllocation, _allocation.__DEPRECATED_effectiveAllocation);
        assertEq(allocation.accRewardsPerAllocatedToken, _allocation.accRewardsPerAllocatedToken);
        assertEq(allocation.distributedRebates, _allocation.distributedRebates);
    }

    function testAllocation_GetAllocationData() public useAllocation {
        (address indexer, bytes32 subgraphDeploymentID, uint256 tokens, uint256 accRewardsPerAllocatedToken) = 
            staking.getAllocationData(_allocationId);
        assertEq(indexer, _allocation.indexer);
        assertEq(subgraphDeploymentID, _allocation.subgraphDeploymentID);
        assertEq(tokens, _allocation.tokens);
        assertEq(accRewardsPerAllocatedToken, _allocation.accRewardsPerAllocatedToken);
    }

    function testAllocation_GetAllocationState_Active() public useAllocation {
        IHorizonStakingExtension.AllocationState state = staking.getAllocationState(_allocationId);
        assertEq(uint16(state), uint16(IHorizonStakingExtension.AllocationState.Active));
    }

    function testAllocation_GetAllocationState_Null() public view {
        IHorizonStakingExtension.AllocationState state = staking.getAllocationState(_allocationId);
        assertEq(uint16(state), uint16(IHorizonStakingExtension.AllocationState.Null));
    }

    function testAllocation_IsAllocation() public useAllocation {
        bool isAllocation = staking.isAllocation(_allocationId);
        assertTrue(isAllocation);
    }

    function testAllocation_IsNotAllocation() public view {
        bool isAllocation = staking.isAllocation(_allocationId);
        assertFalse(isAllocation);
    }
}