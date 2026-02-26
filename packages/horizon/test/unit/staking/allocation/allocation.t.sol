// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingExtension } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingExtension.sol";

contract HorizonStakingAllocationTest is HorizonStakingTest {
    /*
     * TESTS
     */

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
