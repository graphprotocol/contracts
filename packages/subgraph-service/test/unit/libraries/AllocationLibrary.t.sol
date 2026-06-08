// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { AllocationHarness } from "../mocks/AllocationHarness.sol";

contract AllocationLibraryTest is Test {
    AllocationHarness private harness;
    address private allocationId;

    function setUp() public {
        harness = new AllocationHarness();
        allocationId = makeAddr("allocationId");
    }

    function test_Allocation_PresentPOI_RevertWhen_Closed() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        harness.create(address(1), allocationId, bytes32("sdid"), 1000 ether, 0, 1);
        harness.close(allocationId);

        uint256 closedAt = block.timestamp;
        vm.expectRevert(abi.encodeWithSelector(IAllocation.AllocationClosed.selector, allocationId, closedAt));
        harness.presentPOI(allocationId);
    }

    function test_Allocation_ClearPendingRewards_RevertWhen_Closed() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        harness.create(address(1), allocationId, bytes32("sdid"), 1000 ether, 0, 1);
        harness.close(allocationId);

        uint256 closedAt = block.timestamp;
        vm.expectRevert(abi.encodeWithSelector(IAllocation.AllocationClosed.selector, allocationId, closedAt));
        harness.clearPendingRewards(allocationId);
    }

    function test_Allocation_Close_RevertWhen_AlreadyClosed() public {
        // forge-lint: disable-next-line(unsafe-typecast)
        harness.create(address(1), allocationId, bytes32("sdid"), 1000 ether, 0, 1);
        harness.close(allocationId);

        uint256 closedAt = block.timestamp;
        vm.expectRevert(abi.encodeWithSelector(IAllocation.AllocationClosed.selector, allocationId, closedAt));
        harness.close(allocationId);
    }

    function test_Allocation_Get_RevertWhen_NotExists() public {
        address nonExistent = makeAddr("nonExistent");
        vm.expectRevert(abi.encodeWithSelector(IAllocation.AllocationDoesNotExist.selector, nonExistent));
        harness.get(nonExistent);
    }
}
