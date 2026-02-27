// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { Allocation } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocatorTypes.sol";

import { IssuanceAllocatorSharedTest } from "./shared.t.sol";

/// @notice Multi-block distribution accounting tests for IssuanceAllocator.
/// @dev These verify exact token balances across multi-block distribution periods,
///      ported from DefaultTarget.test.ts for functional correctness beyond code coverage.
contract IssuanceAllocatorDistributionAccountingTest is IssuanceAllocatorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @dev Base block number matching shared setUp's vm.roll(1_000_000).
    /// Using a constant avoids Solidity optimizer caching block.number across vm.roll calls.
    uint256 private constant B0 = 1_000_000;

    /// @dev We use 3 simple targets for multi-target accounting.
    /// simpleTarget = target1, trackerTarget = target2, target3 = another MockSimpleTarget
    address internal target3;

    function setUp() public override {
        super.setUp();

        // Deploy a third mock target for multi-target tests
        // We reuse MockSimpleTarget since it supports IIssuanceTarget
        target3 = address(new MockSimpleTarget3());
        vm.label(target3, "Target3");
    }

    // ==================== Default Target Initialization ====================

    function test_InitializesWithDefaultTargetAtIndex0() public view {
        assertEq(allocator.getTargetCount(), 1);
        assertEq(allocator.getTargetAt(0), address(0));
    }

    function test_DefaultTargetGets100PercentAllocation() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory alloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(alloc.totalAllocationRate, ISSUANCE_PER_BLOCK);
        assertEq(alloc.allocatorMintingRate, ISSUANCE_PER_BLOCK);
        assertEq(alloc.selfMintingRate, 0);
    }

    function test_TotalAllocation_ZeroWhenDefaultIsZeroAddress() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        Allocation memory total = allocator.getTotalAllocation();
        // When default is address(0), it's treated as unallocated for reporting
        assertEq(total.totalAllocationRate, 0);
        assertEq(total.allocatorMintingRate, 0);
        assertEq(total.selfMintingRate, 0);
    }

    // ==================== 100% Allocation Invariant ====================

    function test_AutoAdjustDefaultWhenSettingTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 30 ether);

        // Default auto-adjusted to 70 ether
        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory defaultAlloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(defaultAlloc.totalAllocationRate, 70 ether);

        // Reported total excludes default (address(0))
        Allocation memory total = allocator.getTotalAllocation();
        assertEq(total.totalAllocationRate, 30 ether);
    }

    function test_InvariantWithMultipleTargets() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 20 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 35 ether);
        _addTarget(IIssuanceTarget(target3), 15 ether);

        // Default: 100 - 20 - 35 - 15 = 30 ether
        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory defaultAlloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(defaultAlloc.totalAllocationRate, 30 ether);

        Allocation memory total = allocator.getTotalAllocation();
        assertEq(total.totalAllocationRate, 70 ether);
    }

    function test_ZeroDefaultWhenFullyAllocated() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 60 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 40 ether);

        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory defaultAlloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(defaultAlloc.totalAllocationRate, 0);

        Allocation memory total = allocator.getTotalAllocation();
        assertEq(total.totalAllocationRate, ISSUANCE_PER_BLOCK);
    }

    function test_AdjustDefaultWhenRemovingTarget() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 30 ether);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 20 ether);

        // Remove simpleTarget → default goes from 50 to 80
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 0, 0);

        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory defaultAlloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(defaultAlloc.totalAllocationRate, 80 ether);
    }

    function test_SelfMintingInInvariant() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTargetWithSelfMinting(IIssuanceTarget(address(simpleTarget)), 20 ether, 10 ether);
        _addTargetWithSelfMinting(IIssuanceTarget(address(trackerTarget)), 30 ether, 5 ether);

        // Total non-default: 20+10+30+5 = 65. Default: 35.
        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory defaultAlloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(defaultAlloc.totalAllocationRate, 35 ether);

        Allocation memory total = allocator.getTotalAllocation();
        assertEq(total.totalAllocationRate, 65 ether);
        assertEq(total.selfMintingRate, 15 ether);
    }

    // ==================== Multi-Block Distribution Accounting ====================

    function test_NoMintToZeroAddressDefault() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 40 ether);

        vm.roll(B0 + 1);
        allocator.distributeIssuance();

        // simpleTarget gets 40 ether for 1 block
        assertEq(token.balanceOf(address(simpleTarget)), 40 ether);
        // Zero address gets nothing (can't mint to it)
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_MintToDefaultWhenSet() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        vm.prank(governor);
        allocator.setDefaultTarget(target3);
        // Block B0: rate=100, default=target3 at 100%

        vm.roll(B0 + 1);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 30 ether);
        // Distributes 1 block (B0→B0+1): target3 at 100% → 100 to target3
        // Now: simpleTarget=30%, target3(default)=70%

        vm.roll(B0 + 2);
        allocator.distributeIssuance();
        // Distributes 1 block (B0+1→B0+2): simpleTarget=30, target3=70

        assertEq(token.balanceOf(address(simpleTarget)), 30 ether);
        assertEq(token.balanceOf(target3), 170 ether); // 100 + 70
    }

    function test_MultiTargetDistributionAccounting() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        vm.prank(governor);
        allocator.setDefaultTarget(target3);
        // Block B0: rate=100, default=target3 at 100%

        vm.roll(B0 + 1);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 20 ether);
        // Distributes 1 block (B0→B0+1): target3 at 100% → 100 to target3
        // Now: simpleTarget=20%, target3(default)=80%

        vm.roll(B0 + 2);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 30 ether);
        // Distributes 1 block (B0+1→B0+2): simpleTarget=20, target3=80
        // Now: simpleTarget=20%, trackerTarget=30%, target3(default)=50%

        vm.roll(B0 + 3);
        allocator.distributeIssuance();
        // Distributes 1 block (B0+2→B0+3): simpleTarget=20, trackerTarget=30, target3=50

        assertEq(token.balanceOf(address(simpleTarget)), 40 ether); // 20 + 20
        assertEq(token.balanceOf(address(trackerTarget)), 30 ether);
        assertEq(token.balanceOf(target3), 230 ether); // 100 + 80 + 50

        // Total minted = 3 blocks * 100 ether/block
        uint256 totalMinted = token.balanceOf(address(simpleTarget)) +
            token.balanceOf(address(trackerTarget)) +
            token.balanceOf(target3);
        assertEq(totalMinted, 300 ether);
    }

    function test_DistributionWhenDefaultIsZeroPercent() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(simpleTarget)), 60 ether);
        // Block B0: simpleTarget=60%, default(addr(0))=40%

        vm.roll(B0 + 1);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 40 ether);
        // Distributes 1 block (B0→B0+1): simpleTarget=60, addr(0) default=40 (not minted)
        // Now: simpleTarget=60%, trackerTarget=40%, default(addr(0))=0%

        vm.roll(B0 + 2);
        allocator.distributeIssuance();
        // Distributes 1 block (B0+1→B0+2): simpleTarget=60, trackerTarget=40

        assertEq(token.balanceOf(address(simpleTarget)), 120 ether); // 60 + 60
        assertEq(token.balanceOf(address(trackerTarget)), 40 ether);
        assertEq(token.balanceOf(address(0)), 0);

        Allocation memory defaultAlloc = allocator.getTargetAllocation(address(0));
        assertEq(defaultAlloc.totalAllocationRate, 0);
    }

    function test_DefaultTargetMaintainsAllocationAfterChange() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 40 ether);

        // Default has 60 ether at address(0)
        address defaultAddr = allocator.getTargetAt(0);
        Allocation memory alloc = allocator.getTargetAllocation(defaultAddr);
        assertEq(alloc.totalAllocationRate, 60 ether);

        // Change default to simpleTarget
        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));

        // New default should inherit 60 ether
        assertEq(allocator.getTargetAt(0), address(simpleTarget));
        alloc = allocator.getTargetAllocation(address(simpleTarget));
        assertEq(alloc.totalAllocationRate, 60 ether);

        // Old address(0) should be zeroed
        alloc = allocator.getTargetAllocation(address(0));
        assertEq(alloc.totalAllocationRate, 0);
    }

    function test_TotalAllocation100PercentWithRealDefault() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 30 ether);

        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));

        Allocation memory total = allocator.getTotalAllocation();
        assertEq(total.totalAllocationRate, ISSUANCE_PER_BLOCK);
        assertEq(total.allocatorMintingRate, ISSUANCE_PER_BLOCK);
    }

    function test_TotalMintedEqualsBlocksTimesRate() public {
        _setIssuanceRate(ISSUANCE_PER_BLOCK);
        vm.prank(governor);
        allocator.setDefaultTarget(address(simpleTarget));
        // Block B0: rate=100, default=simpleTarget at 100%

        vm.roll(B0 + 1);
        _addTarget(IIssuanceTarget(address(trackerTarget)), 40 ether);
        // Distributes 1 block (B0→B0+1): simpleTarget(default) at 100% → 100 to simpleTarget
        // Now: simpleTarget(default)=60%, trackerTarget=40%

        vm.roll(B0 + 11);
        allocator.distributeIssuance();
        // Distributes 10 blocks (B0+1→B0+11): simpleTarget=60*10=600, trackerTarget=40*10=400

        uint256 totalMinted = token.balanceOf(address(simpleTarget)) + token.balanceOf(address(trackerTarget));
        // 1 block at 100% + 10 blocks at full rate = 11 blocks * 100 ether
        assertEq(totalMinted, ISSUANCE_PER_BLOCK * 11);
    }

    /* solhint-enable graph/func-name-mixedcase */
}

import { MockSimpleTarget } from "../../../contracts/test/allocate/MockSimpleTarget.sol";

/// @dev Second instance of MockSimpleTarget for use as target3.
contract MockSimpleTarget3 is MockSimpleTarget {}
