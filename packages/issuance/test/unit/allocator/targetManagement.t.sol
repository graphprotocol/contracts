// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import {
    Allocation,
    AllocationTarget
} from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";

import { IssuanceAllocator } from "../../../contracts/allocate/IssuanceAllocator.sol";
import { IssuanceAllocatorSharedTest } from "./shared.t.sol";

/// @notice Target management tests for IssuanceAllocator.
contract IssuanceAllocatorTargetManagementTest is IssuanceAllocatorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Adding Targets ====================

    function test_AddTarget_SupportsIIssuanceTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        assertEq(allocator.getTargetCount(), 2); // default + simpleTarget
    }

    function test_Revert_AddEOATarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        address eoa = makeAddr("eoa");

        // EOAs have no code, so ERC-165 supportsInterface call fails with empty revert data
        vm.expectRevert();
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(eoa), 10 ether);
    }

    function test_Revert_AddNonIIssuanceTargetContract() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.expectRevert(
            abi.encodeWithSelector(IssuanceAllocator.TargetDoesNotSupportIIssuanceTarget.selector, address(nonTarget))
        );
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(nonTarget)), 10 ether);
    }

    function test_Revert_AddRevertingTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Even though it supports IIssuanceTarget, notification reverts
        vm.expectRevert();
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(revertingTarget)), 10 ether);
    }

    function test_AddTarget_ReAddExistingTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        // Re-add same target with different allocation — should update, not duplicate
        _addTarget(IIssuanceTarget(address(simpleTarget)), 20 ether);
        assertEq(allocator.getTargetCount(), 2);

        Allocation memory alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.allocatorMintingRate, 20 ether);
    }

    // ==================== Removing Targets ====================

    function test_RemoveTarget_SetAllocationToZero() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        assertEq(allocator.getTargetCount(), 2);

        // Set allocation to 0 removes the target
        _addTarget(IIssuanceTarget(address(simpleTarget)), 0);
        assertEq(allocator.getTargetCount(), 1);
    }

    function test_RemoveTarget_WhenMultipleExist() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 20 ether);
        assertEq(allocator.getTargetCount(), 3);

        _addTarget(IIssuanceTarget(address(simpleTarget)), 0);
        assertEq(allocator.getTargetCount(), 2);
    }

    function test_RemoveTarget_SecondNonDefault_CoversLoopIncrement() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether); // index 1
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether); // index 2
        assertEq(allocator.getTargetCount(), 3);

        // Remove trackerTarget (at index 2), forcing _removeTarget loop to execute ++i past index 1
        _addTarget(IIssuanceTarget(address(trackerTarget)), 0);
        assertEq(allocator.getTargetCount(), 2);
        assertEq(allocator.getTargetAt(1), address(simpleTarget));
    }

    // ==================== Allocation Constraints ====================

    function test_Revert_AllocationExceedsBudget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.expectRevert();
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), ISSUANCE_PER_BLOCK + 1);
    }

    function test_AllocationExactlyEqualsBudget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), ISSUANCE_PER_BLOCK);

        Allocation memory alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.allocatorMintingRate, ISSUANCE_PER_BLOCK);
    }

    // ==================== Self-Minting Targets ====================

    function test_SelfMintingTarget_NotMintedByAllocator() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 0, 10 ether);

        vm.roll(block.number + 10);
        allocator.distributeIssuance();

        // Self-minting target should not receive tokens from allocator
        assertEq(token.balanceOf(address(simpleTarget)), 0);
    }

    function test_SelfMintingTarget_UpdateFlag() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 0, 10 ether);

        Allocation memory alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.selfMintingRate, 10 ether);
        assertEq(alloc.allocatorMintingRate, 0);

        // Change to allocator-minting
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.allocatorMintingRate, 10 ether);
        assertEq(alloc.selfMintingRate, 0);
    }

    // ==================== Access Control ====================

    function test_Revert_NonGovernorCannotSetAllocation() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), 10 ether);
    }

    function test_NonGovernorCanDistributeIssuance() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        vm.roll(block.number + 1);

        vm.prank(unauthorized);
        allocator.distributeIssuance();
    }

    // ==================== Idempotent Operations ====================

    function test_Idempotent_OperateOnNonExistentTarget() public {
        // Setting allocation to 0 for non-existent target should not revert
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), 0);
    }

    // ==================== Default Target ====================

    function test_Revert_CannotSetAllocationForDefaultTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Set a default target first
        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));

        // Cannot set allocation for the default target
        vm.expectRevert(
            abi.encodeWithSelector(
                IssuanceAllocator.CannotSetAllocationForDefaultTarget.selector,
                address(simpleTarget)
            )
        );
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), 10 ether);
    }

    // ==================== Default Target Management ====================

    function test_SetDefaultTarget_CannotSetAllocatedTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IssuanceAllocator.CannotSetDefaultToAllocatedTarget.selector, address(simpleTarget))
        );
        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));
    }

    function test_SetDefaultTarget_WithMinDistributedBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.roll(block.number + 1);
        vm.prank(governor);
        allocator.setDefaultTarget(address(trackerTarget), block.number);

        assertEq(allocator.getTargetAt(0), address(trackerTarget));
    }

    // ==================== 4-Param setTargetAllocation ====================

    function test_SetTargetAllocation_4Param() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.roll(block.number + 1);
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), 10 ether, 5 ether, block.number);

        Allocation memory alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.allocatorMintingRate, 10 ether);
        assertEq(alloc.selfMintingRate, 5 ether);
    }

    // ==================== Additional View Functions ====================

    function test_GetTargets() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        address[] memory targets = allocator.getTargets();
        assertEq(targets.length, 3);
        assertEq(targets[0], address(0)); // default
        assertEq(targets[1], address(simpleTarget));
        assertEq(targets[2], address(trackerTarget));
    }

    function test_GetTargetData() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        AllocationTarget memory data = allocator.getTargetData(address(simpleTarget));
        assertEq(data.allocatorMintingRate, 10 ether);
        assertEq(data.selfMintingRate, 0);
        assertEq(data.lastChangeNotifiedBlock, block.number);
    }

    function test_GetTotalAllocation() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 30 ether);
        _addTargetWithSelfMinting(IIssuanceTarget(address(trackerTarget)), 10 ether, 5 ether);

        Allocation memory total = allocator.getTotalAllocation();
        // Default target is address(0), so its allocation is excluded
        // allocatorMintingRate for non-default = 30 + 10 = 40
        // selfMintingRate = 5
        // totalAllocationRate = issuancePerBlock - defaultAllocatorMintingRate
        assertEq(total.selfMintingRate, 5 ether);
        assertEq(total.allocatorMintingRate, 40 ether);
        assertEq(total.totalAllocationRate, 45 ether);
    }

    function test_GetTotalAllocation_WithRealDefaultTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Set a real default target
        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));

        Allocation memory total = allocator.getTotalAllocation();
        // With real default, all issuance is accounted
        assertEq(total.totalAllocationRate, ISSUANCE_PER_BLOCK);
    }

    // ==================== Idempotent / Early-Return Branches ====================

    function test_SetDefaultTarget_SameAddress_NoOp() public {
        // Default is address(0) initially; setting to same should be no-op (line 915)
        address current = allocator.getTargetAt(0);
        assertEq(current, address(0));

        vm.prank(governor);
        allocator.setDefaultTarget(address(0));

        assertEq(allocator.getTargetAt(0), address(0));
    }

    function test_SetDefaultTarget_ReturnsFalse_WhenPaused() public {
        // Pause → setDefaultTarget with high minDistributedBlock → returns false (line 926)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        allocator.distributeIssuance();

        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 3);

        // minDistributedBlock = block.number, but lastDistributionBlock is frozen behind
        vm.prank(governor);
        bool result = allocator.setDefaultTarget(address(trackerTarget), block.number);
        assertFalse(result);
        // Default unchanged
        assertEq(allocator.getTargetAt(0), address(0));
    }

    function test_SetTargetAllocation_ReturnsFalse_WhenPaused() public {
        // Pause → 4-param setTargetAllocation with high minDistributedBlock → returns false (line 964)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        allocator.distributeIssuance();

        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 3);

        vm.prank(governor);
        bool result = allocator.setTargetAllocation(IIssuanceTarget(address(simpleTarget)), 10 ether, 0, block.number);
        assertFalse(result);
    }

    function test_Revert_SetTargetAllocation_ZeroAddress() public {
        // Setting allocation for address(0) should revert with TargetAddressCannotBeZero (line 998)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.expectRevert(abi.encodeWithSelector(IssuanceAllocator.TargetAddressCannotBeZero.selector));
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(0)), 10 ether);
    }

    function test_SetDefaultTarget_CannotSetAllocatedTarget_LoopHit() public {
        // Tests the require inside the for-loop (line 923) with multiple allocated targets
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        // Try to set trackerTarget as default — should revert at i=2 in the loop
        vm.expectRevert(
            abi.encodeWithSelector(IssuanceAllocator.CannotSetDefaultToAllocatedTarget.selector, address(trackerTarget))
        );
        vm.prank(governor);
        allocator.setDefaultTarget(address(trackerTarget));
    }

    /* solhint-enable graph/func-name-mixedcase */
}
