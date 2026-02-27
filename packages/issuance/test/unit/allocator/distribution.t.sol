// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import {
    TargetIssuancePerBlock,
    DistributionState,
    SelfMintingEventMode
} from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";

import { MockReentrantTarget } from "../../../contracts/test/allocate/MockReentrantTarget.sol";
import { IssuanceAllocatorSharedTest } from "./shared.t.sol";

/// @notice Distribution and issuance tests for IssuanceAllocator.
contract IssuanceAllocatorDistributionTest is IssuanceAllocatorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ==================== Basic Distribution ====================

    function test_DistributeIssuance_MintsTokensToTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        vm.roll(block.number + 5);
        allocator.distributeIssuance();

        assertEq(token.balanceOf(address(simpleTarget)), 50 ether);
    }

    function test_DistributeIssuance_UpdatesLastDistributionBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        vm.roll(block.number + 5);
        uint256 result = allocator.distributeIssuance();
        assertEq(result, block.number);
        assertEq(allocator.getDistributionState().lastDistributionBlock, block.number);
    }

    function test_DistributeIssuance_NoOpSameBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        vm.roll(block.number + 1);
        allocator.distributeIssuance();
        uint256 balanceBefore = token.balanceOf(address(simpleTarget));

        // Same block — no additional minting
        allocator.distributeIssuance();
        assertEq(token.balanceOf(address(simpleTarget)), balanceBefore);
    }

    function test_DistributeIssuance_ZeroIssuance() public {
        // issuancePerBlock is 0 by default
        vm.roll(block.number + 10);
        allocator.distributeIssuance();
        // Should not revert, just advance blocks
    }

    function test_DistributeIssuance_NotPausedWhenDistributing() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        // Pause
        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 5);
        uint256 result = allocator.distributeIssuance();

        // Should return frozen lastDistributionBlock, not current block
        assertLt(result, block.number);
        // No tokens minted
        assertEq(token.balanceOf(address(simpleTarget)), 0);
    }

    // ==================== Issuance Rate Management ====================

    function test_SetIssuancePerBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        assertEq(allocator.getIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    function test_SetIssuancePerBlock_NotifiesDefaultTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Set trackerTarget as default target so it gets notified on rate change
        vm.prank(governor);
        allocator.setDefaultTarget(address(trackerTarget));

        vm.roll(block.number + 1);
        trackerTarget.resetNotificationCount();

        _setIssuanceRate(200 ether);
        // setIssuancePerBlock only notifies the default target
        assertEq(trackerTarget.notificationCount(), 1);
    }

    function test_Revert_DecreaseRateBelowAllocated() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 50 ether);

        vm.roll(block.number + 1);

        // Try to decrease below what's allocated
        vm.expectRevert();
        vm.prank(governor);
        allocator.setIssuancePerBlock(40 ether);
    }

    function test_Revert_NonGovernorCannotSetIssuanceRate() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        allocator.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
    }

    // ==================== Notification Behavior ====================

    function test_OnlyNotifyTargetOncePerBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        trackerTarget.resetNotificationCount();

        // Same block — notification via notifyTarget should be skipped
        vm.prank(governor);
        allocator.notifyTarget(address(trackerTarget));
        assertEq(trackerTarget.notificationCount(), 0); // already notified this block
    }

    function test_NotifyTarget_NewBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        trackerTarget.resetNotificationCount();
        vm.roll(block.number + 1);

        vm.prank(governor);
        allocator.notifyTarget(address(trackerTarget));
        assertEq(trackerTarget.notificationCount(), 1);
    }

    function test_Revert_NotifyNonExistentTarget() public {
        // Calling notifyTarget on an EOA reverts because the external call
        // to IIssuanceTarget.beforeIssuanceAllocationChange() fails
        address eoa = makeAddr("eoa");
        vm.expectRevert();
        vm.prank(governor);
        allocator.notifyTarget(eoa);
    }

    function test_Revert_NotificationFailsOnRevertingTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Trying to add a reverting target should fail
        vm.expectRevert();
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(revertingTarget)), 10 ether);
    }

    // ==================== Force Change Notification Block ====================

    function test_ForceTargetNoChangeNotificationBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        // Force set to current block — should prevent notification this block
        vm.prank(governor);
        allocator.forceTargetNoChangeNotificationBlock(address(trackerTarget), block.number);

        trackerTarget.resetNotificationCount();
        vm.prank(governor);
        allocator.notifyTarget(address(trackerTarget));
        assertEq(trackerTarget.notificationCount(), 0);
    }

    function test_ForceTargetNoChangeNotificationBlock_PastBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);

        vm.roll(block.number + 1);

        // Force set to past block — notification should be enabled
        vm.prank(governor);
        allocator.forceTargetNoChangeNotificationBlock(address(trackerTarget), block.number - 2);

        trackerTarget.resetNotificationCount();
        vm.prank(governor);
        allocator.notifyTarget(address(trackerTarget));
        assertEq(trackerTarget.notificationCount(), 1);
    }

    // ==================== View Functions ====================

    function test_GetTargetIssuancePerBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        TargetIssuancePerBlock memory info = allocator.getTargetIssuancePerBlock(address(simpleTarget));
        assertEq(info.allocatorIssuanceRate, 10 ether);
    }

    function test_GetTargetCount() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        assertEq(allocator.getTargetCount(), 1); // just default

        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);
        assertEq(allocator.getTargetCount(), 2);

        _addTarget(IIssuanceTarget(address(trackerTarget)), 10 ether);
        assertEq(allocator.getTargetCount(), 3);
    }

    function test_GetTargetAddress() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        assertEq(allocator.getTargetAt(0), address(0)); // default
        assertEq(allocator.getTargetAt(1), address(simpleTarget));
    }

    function test_GetDistributionState() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        DistributionState memory state = allocator.getDistributionState();
        assertEq(state.lastDistributionBlock, block.number);
    }

    function test_GetIssuancePerBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        assertEq(allocator.getIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    // ==================== Self-Minting Event Modes ====================

    function test_SetSelfMintingEventMode() public {
        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.Aggregate);

        // No direct getter, but we can verify it doesn't revert
        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.None);
    }

    // ==================== Pending Issuance Distribution ====================

    function test_DistributePendingIssuance_WithSelfMinting() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 10 ether, 10 ether);

        // Pause to accumulate self-minting offset
        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 10);
        allocator.distributeIssuance(); // self-minting tracked during pause

        // Unpause
        vm.prank(governor);
        allocator.unpause();

        // Distribute pending
        vm.roll(block.number + 1);
        allocator.distributeIssuance();
    }

    function test_Revert_NonGovernorCannotCallDistributePendingIssuance() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        allocator.distributePendingIssuance();
    }

    function test_Revert_ToBlockOutOfRange_Future() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.expectRevert();
        vm.prank(governor);
        allocator.distributePendingIssuance(block.number + 100);
    }

    // ==================== Pause/Unpause Edge Cases ====================

    function test_UnpauseResumeDistribution() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 10 ether);

        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);

        vm.roll(block.number + 5);
        allocator.distributeIssuance();
        uint256 balanceBeforePause = token.balanceOf(address(simpleTarget));

        // Pause
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 10);

        // Unpause
        vm.prank(governor);
        allocator.unpause();

        vm.roll(block.number + 1);
        allocator.distributeIssuance();

        // Should have minted tokens for blocks during pause + 1 after unpause
        assertGt(token.balanceOf(address(simpleTarget)), balanceBeforePause);
    }

    // ==================== ERC-165 Interface Support ====================

    function test_SupportsInterface_ERC165() public view {
        assertTrue(allocator.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_Unknown() public view {
        assertFalse(allocator.supportsInterface(bytes4(0xdeadbeef)));
    }

    // ==================== Self-Minting Event Modes (Aggregate) ====================

    function test_SelfMintingEventMode_Aggregate() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 10 ether, 10 ether);

        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.Aggregate);

        vm.roll(block.number + 5);
        allocator.distributeIssuance();

        // Verify tokens were minted for allocator-minting portion
        assertEq(token.balanceOf(address(simpleTarget)), 50 ether);
    }

    function test_SelfMintingEventMode_PerTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 10 ether, 10 ether);

        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.PerTarget);

        vm.roll(block.number + 5);
        allocator.distributeIssuance();

        assertEq(token.balanceOf(address(simpleTarget)), 50 ether);
    }

    function test_GetSelfMintingEventMode() public {
        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.Aggregate);
        assertEq(uint256(allocator.getSelfMintingEventMode()), uint256(SelfMintingEventMode.Aggregate));
    }

    // ==================== 2-Param setIssuancePerBlock ====================

    function test_SetIssuancePerBlock_WithMinDistributedBlock() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.roll(block.number + 1);
        vm.prank(governor);
        allocator.setIssuancePerBlock(200 ether, block.number);
        assertEq(allocator.getIssuancePerBlock(), 200 ether);
    }

    // ==================== Pending Issuance: 0-param distributePendingIssuance ====================

    function test_DistributePendingIssuance_ZeroParam() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 10 ether, 10 ether);

        // Pause to accumulate self-minting offset
        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 10);
        allocator.distributeIssuance(); // self-minting tracked during pause

        // Unpause
        vm.prank(governor);
        allocator.unpause();

        // Use 0-param version (distributes to current block)
        vm.roll(block.number + 1);
        vm.prank(governor);
        allocator.distributePendingIssuance();
    }

    // ==================== Pending Distribution: Proportional Case ====================

    function test_DistributePendingIssuance_Proportional() public {
        // Trigger proportional distribution: available < allocatedTotal
        // Key: pause for N blocks to accumulate offset, then distribute for only
        // a small sub-period so offset >> totalForPeriod for that sub-period.
        vm.prank(governor);
        allocator.setIssuancePerBlock(1000 ether);

        // target1: 400 allocator, target2: 400 allocator + 150 self. Default: 50
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 400 ether, 0);
        _addTargetWithSelfMinting(IIssuanceTarget(address(trackerTarget)), 400 ether, 150 ether);

        allocator.distributeIssuance();

        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        // Pause for 10 blocks → selfMintingOffset = 150 * 10 = 1500
        vm.roll(block.number + 10);

        uint256 lastDistBlock = allocator.getDistributionState().lastDistributionBlock;

        // Advance self-minting via distributeIssuance while paused
        allocator.distributeIssuance();

        // Unpause
        vm.prank(governor);
        allocator.unpause();

        // Distribute for only 2 of the 10 paused blocks:
        // totalForPeriod = 1000 * 2 = 2000
        // available = 2000 - 1500 = 500
        // allocatedTotal = (400+400) * 2 = 1600
        // 500 < 1600 → proportional distribution!
        uint256 partialBlock = lastDistBlock + 2;

        uint256 balBefore1 = token.balanceOf(address(simpleTarget));
        uint256 balBefore2 = token.balanceOf(address(trackerTarget));

        vm.prank(governor);
        allocator.distributePendingIssuance(partialBlock);

        // Both targets receive proportional shares
        uint256 received1 = token.balanceOf(address(simpleTarget)) - balBefore1;
        uint256 received2 = token.balanceOf(address(trackerTarget)) - balBefore2;
        assertGt(received1, 0);
        assertGt(received2, 0);
        // Same allocator rate (400 each) → same proportional share
        assertEq(received1, received2);
    }

    // ==================== Distribution: Default Target Gets Remainder ====================

    function test_DistributePendingIssuance_DefaultGetsRemainder() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Set a real default target
        vm.prank(governor);
        allocator.setDefaultTarget(address(trackerTarget));

        _addTarget(IIssuanceTarget(address(simpleTarget)), 30 ether);

        // Pause to build self-minting offset
        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);

        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 30 ether, 10 ether);

        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 5);
        allocator.distributeIssuance(); // self-minting tracked

        vm.prank(governor);
        allocator.unpause();

        vm.roll(block.number + 1);
        allocator.distributeIssuance();

        // Default target should have received some remainder
        assertGt(token.balanceOf(address(trackerTarget)), 0);
    }

    // ==================== Reentrancy Protection ====================

    function test_Revert_ReentrantSetTargetAllocation() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        // Set up reentrant target
        reentrantTarget.setIssuanceAllocator(address(allocator));
        reentrantTarget.setReentrantAction(MockReentrantTarget.ReentrantAction.SetTargetAllocation1Param);

        // Adding the target should fail due to reentrancy in notification callback
        vm.expectRevert();
        vm.prank(governor);
        allocator.setTargetAllocation(IIssuanceTarget(address(reentrantTarget)), 10 ether);
    }

    // ==================== Idempotent / Early-Return Branches ====================

    function test_SetIssuancePerBlock_SameValue_NoOp() public {
        // Setting same rate should return true without distributing (line 731)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);

        vm.roll(block.number + 1);

        vm.prank(governor);
        bool result = allocator.setIssuancePerBlock(ISSUANCE_PER_BLOCK);
        assertTrue(result);
    }

    function test_SetIssuancePerBlock_ReturnsFalse_WhenPaused() public {
        // Pause → 2-param setIssuancePerBlock with high minDistributedBlock → returns false (line 733)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        allocator.distributeIssuance();

        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();

        vm.roll(block.number + 3);

        vm.prank(governor);
        bool result = allocator.setIssuancePerBlock(200 ether, block.number);
        assertFalse(result);
        // Rate unchanged
        assertEq(allocator.getIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    function test_SetSelfMintingEventMode_SameMode_NoOp() public {
        // Default mode is PerTarget; setting same mode should be no-op (line 760)
        vm.prank(governor);
        allocator.setSelfMintingEventMode(SelfMintingEventMode.Aggregate);

        // Set same again
        vm.prank(governor);
        bool result = allocator.setSelfMintingEventMode(SelfMintingEventMode.Aggregate);
        assertTrue(result);
    }

    function test_DistributePendingIssuance_BlocksEqZero() public {
        // distributePendingIssuance(toBlock) where toBlock == lastDistributionBlock → blocks == 0 (line 543)
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 10 ether, 10 ether);

        // Pause, accumulate offset, unpause
        vm.prank(governor);
        allocator.grantRole(PAUSE_ROLE, governor);
        vm.prank(governor);
        allocator.pause();
        vm.roll(block.number + 5);
        allocator.distributeIssuance();
        vm.prank(governor);
        allocator.unpause();

        uint256 lastDistBlock = allocator.getDistributionState().lastDistributionBlock;

        // Call distributePendingIssuance with toBlock == lastDistBlock → blocks == 0
        vm.prank(governor);
        uint256 result = allocator.distributePendingIssuance(lastDistBlock);
        assertEq(result, lastDistBlock);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
