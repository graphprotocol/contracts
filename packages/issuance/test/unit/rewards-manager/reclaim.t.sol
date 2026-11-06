// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerReclaimTest is RewardsManagerSharedTest {
    event ReclaimAddressSet(bytes32 indexed reason, address indexed oldAddress, address indexed newAddress);
    event DefaultReclaimAddressSet(address indexed oldAddress, address indexed newAddress);
    event RewardsReclaimed(
        bytes32 indexed reason,
        uint256 amount,
        address indexed indexer,
        address indexed allocationID,
        bytes32 subgraphDeploymentID
    );
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsDenied(address indexed indexer, address indexed allocationID);
    event RewardsDeniedDueToEligibility(address indexed indexer, address indexed allocationID, uint256 amount);

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");
    uint256 internal constant MINIMUM_SIGNAL = 1000 ether;
    uint256 internal constant BELOW_MINIMUM = 500 ether;
    /// Blocks mined by the old `helpers.mine(5)`
    uint256 internal constant MINED_BLOCKS = 5;

    address internal allocationID1 = makeAddr("allocationID1");
    address internal reclaimWallet = makeAddr("reclaimWallet");
    address internal otherWallet = makeAddr("otherWallet");

    // -- Helpers --

    /// Rewards of the single allocation over `EPOCH_LENGTH` blocks.
    function _epochAllocationRewards() internal pure returns (uint256) {
        return _expectedAllocationRewards(EPOCH_LENGTH, ALLOCATION, ALLOCATION);
    }

    function _setDefaultReclaimAddress(address target) internal {
        vm.prank(governor);
        rm.setDefaultReclaimAddress(target);
    }

    function _deny() internal {
        _setAvailabilityOracle(governor);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
    }

    /// Allocation data on the issuer, as the old test's `MockSubgraphService.setAllocation`.
    function _setActiveIssuerAllocation(bool isActive) internal {
        issuer.setAllocation(allocationID1, isActive, indexer, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION, 0, 0);
        issuer.setSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
    }

    function _triggerAllocationUpdate() internal {
        vm.prank(governor);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID_1);
    }

    modifier withMinimumSignal() {
        vm.prank(governor);
        rm.setMinimumSubgraphSignal(MINIMUM_SIGNAL);
        _;
    }

    /// Old `default reclaim address fallback` beforeEach.
    modifier withAllocationAndAvailabilityOracle() {
        _signalThenAllocate(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
        _setAvailabilityOracle(governor);
        _;
    }

    // -- setReclaimAddress --

    function test_SetReclaimAddress_RevertWhen_NotGovernor() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Only Controller governor"));
        rm.setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);
    }

    function test_SetReclaimAddress_RevertWhen_ReasonIsNone() public {
        vm.prank(governor);
        vm.expectRevert(bytes("Cannot set reclaim address for NONE"));
        rm.setReclaimAddress(RewardsCondition.NONE, reclaimWallet);
    }

    function test_SetReclaimAddress_SetsEligibilityReclaimAddressAsGovernor() public {
        vm.expectEmit(address(rm));
        emit ReclaimAddressSet(RewardsCondition.INDEXER_INELIGIBLE, address(0), reclaimWallet);
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);

        assertEq(rm.getReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE), reclaimWallet);
    }

    function test_SetReclaimAddress_SetsSubgraphDeniedReclaimAddressAsGovernor() public {
        vm.expectEmit(address(rm));
        emit ReclaimAddressSet(RewardsCondition.SUBGRAPH_DENIED, address(0), reclaimWallet);
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);

        assertEq(rm.getReclaimAddress(RewardsCondition.SUBGRAPH_DENIED), reclaimWallet);
    }

    function test_SetReclaimAddress_AllowsSettingToZeroAddress() public {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);

        vm.expectEmit(address(rm));
        emit ReclaimAddressSet(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet, address(0));
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, address(0));

        assertEq(rm.getReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE), address(0));
    }

    function test_SetReclaimAddress_NoEventWhenSettingSameAddress() public {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);

        vm.recordLogs();
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);
        _assertNotEmitted(vm.getRecordedLogs(), ReclaimAddressSet.selector);
    }

    // -- reclaim denied rewards - subgraph denylist --
    // Denied before the allocation: the accumulator is frozen, rewards are reclaimed at the subgraph level
    // (address(0) indexer and allocation) and the allocation has none at close.

    function test_ReclaimDeniedRewardsSubgraphDenylist_MintsToReclaimAddressWhenSet() public {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _deny();
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        uint256 expectedRewards = _subgraphRewards(EPOCH_LENGTH);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.recordLogs();
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsDenied.selector);

        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimDeniedRewardsSubgraphDenylist_ReclaimsPreDenialRewardsWhenDeniedAfterAllocation() public {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setAvailabilityOracle(governor);

        // Allocate first, then deny: the pre-denial rewards stay with the allocation
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        // Close in the next block, as in Hardhat: that block is reclaimed at the subgraph level
        vm.roll(block.number + 1);

        uint256 allocationRewards = _epochAllocationRewards();
        uint256 subgraphLevelRewards = _subgraphRewards(1);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            subgraphLevelRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        vm.expectEmit(address(rm), 1);
        emit RewardsDenied(indexer, allocationID1);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            allocationRewards,
            indexer,
            allocationID1,
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);

        assertGe(token.balanceOf(reclaimWallet) - balanceBefore, allocationRewards);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, allocationRewards + subgraphLevelRewards);
    }

    function test_ReclaimDeniedRewardsSubgraphDenylist_NoMintWhenReclaimAddressNotSet() public {
        _deny();
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsReclaimed.selector);
    }

    // -- reclaim denied rewards - eligibility --

    function test_ReclaimDeniedRewardsEligibility_MintsToReclaimAddressWhenSet() public {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);
        _useEligibilityOracle(false);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        uint256 expectedRewards = _epochAllocationRewards();
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.INDEXER_INELIGIBLE,
            expectedRewards,
            indexer,
            allocationID1,
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);

        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimDeniedRewardsEligibility_NoMintWhenReclaimAddressNotSet() public {
        _useEligibilityOracle(false);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        vm.expectEmit(address(rm), 1);
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, _epochAllocationRewards());
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
    }

    // -- reclaim precedence - first successful reclaim wins --

    function test_ReclaimPrecedenceFirstSuccessfulReclaimWins_ReclaimsToSubgraphDeniedWhenBothConfigured() public {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, otherWallet);
        _deny();
        _useEligibilityOracle(false);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        uint256 expectedRewards = _subgraphRewards(EPOCH_LENGTH);
        uint256 subgraphDeniedBalanceBefore = token.balanceOf(reclaimWallet);
        uint256 indexerIneligibleBalanceBefore = token.balanceOf(otherWallet);

        vm.recordLogs();
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);

        assertEq(token.balanceOf(reclaimWallet) - subgraphDeniedBalanceBefore, expectedRewards);
        assertEq(token.balanceOf(otherWallet), indexerIneligibleBalanceBefore);
    }

    function test_ReclaimPrecedenceFirstSuccessfulReclaimWins_DropsWhenOnlyIndexerIneligibleConfigured() public {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, otherWallet);
        _deny();
        _useEligibilityOracle(false);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        uint256 balanceBefore = token.balanceOf(otherWallet);

        // Subgraph-level denial without a SUBGRAPH_DENIED address: dropped, and the eligibility path is not reached
        vm.recordLogs();
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);
        _assertNotEmitted(logs, RewardsReclaimed.selector);

        assertEq(token.balanceOf(otherWallet), balanceBefore);
    }

    function test_ReclaimPrecedenceFirstSuccessfulReclaimWins_FallsBackToIndexerIneligibleForPreDenialAllocation()
        public
    {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);
        _setAvailabilityOracle(governor);
        _useEligibilityOracle(false);

        // Allocate first, then deny, so the rewards reach `_deniedRewards`
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + 1);

        uint256 expectedRewards = _epochAllocationRewards();
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        // Both conditions hold; with no SUBGRAPH_DENIED address the reason falls back to INDEXER_INELIGIBLE
        vm.expectEmit(address(rm));
        emit RewardsDenied(indexer, allocationID1);
        vm.expectEmit(address(rm));
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, expectedRewards);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.INDEXER_INELIGIBLE,
            expectedRewards,
            indexer,
            allocationID1,
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);

        // The subgraph-level block after the denial has no SUBGRAPH_DENIED address and is dropped
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimPrecedenceFirstSuccessfulReclaimWins_DropsWhenNeitherAddressConfigured() public {
        _deny();
        _useEligibilityOracle(false);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);
        _assertNotEmitted(logs, RewardsReclaimed.selector);
    }

    function test_ReclaimPrecedenceFirstSuccessfulReclaimWins_DropsWhenSubgraphDeniedWithoutAddressEvenIfEligible()
        public
    {
        _deny();
        _useEligibilityOracle(true);
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        vm.recordLogs();
        _close(allocationID1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertNotEmitted(logs, RewardsDenied.selector);
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);
        _assertNotEmitted(logs, RewardsReclaimed.selector);
        _assertNotEmitted(logs, HorizonRewardsAssigned.selector);
    }

    // -- reclaimRewards - force close allocation --
    // `issuer` replaces the old MockSubgraphService; the legacy Staking allocation is not needed, since
    // RewardsManager only reads allocation data from the subgraph service.

    function test_ReclaimRewardsForceCloseAllocation_ReclaimsWhenReclaimAddressSet() public {
        _setReclaimAddress(RewardsCondition.CLOSE_ALLOCATION, reclaimWallet);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveIssuerAllocation(true);
        vm.roll(block.number + EPOCH_LENGTH);

        uint256 expectedRewards = _epochAllocationRewards();
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.CLOSE_ALLOCATION,
            expectedRewards,
            indexer,
            allocationID1,
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        uint256 reclaimed = issuer.reclaim(RewardsCondition.CLOSE_ALLOCATION, allocationID1);

        uint256 rewardsClaimed = token.balanceOf(reclaimWallet) - balanceBefore;
        assertGt(rewardsClaimed, 0);
        assertEq(rewardsClaimed, expectedRewards);
        assertEq(reclaimed, expectedRewards);
    }

    function test_ReclaimRewardsForceCloseAllocation_NoReclaimWhenReclaimAddressNotSet() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveIssuerAllocation(true);
        vm.roll(block.number + EPOCH_LENGTH);

        vm.recordLogs();
        uint256 reclaimed = issuer.reclaim(RewardsCondition.CLOSE_ALLOCATION, allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
        assertEq(reclaimed, 0);
    }

    function test_ReclaimRewardsForceCloseAllocation_ReturnsZeroWhenNoAddressAndNoRewards() public {
        // Inactive allocation: no rewards
        _setActiveIssuerAllocation(false);

        vm.recordLogs();
        uint256 reclaimed = issuer.reclaim(RewardsCondition.CLOSE_ALLOCATION, allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
        assertEq(reclaimed, 0);
    }

    function test_ReclaimRewardsForceCloseAllocation_ReturnsZeroWhenReasonIsNone() public {
        // A default reclaim address makes the NONE guard, not a missing address, the reason for 0
        _setDefaultReclaimAddress(reclaimWallet);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _setActiveIssuerAllocation(true);
        vm.roll(block.number + EPOCH_LENGTH);

        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.recordLogs();
        uint256 reclaimed = issuer.reclaim(RewardsCondition.NONE, allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
        assertEq(reclaimed, 0);
        assertEq(token.balanceOf(reclaimWallet), balanceBefore);
    }

    function test_ReclaimRewardsForceCloseAllocation_RevertWhen_CalledByUnauthorizedAddress() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Not a rewards issuer"));
        rm.reclaimRewards(RewardsCondition.CLOSE_ALLOCATION, allocationID1);
    }

    // -- setDefaultReclaimAddress --

    function test_SetDefaultReclaimAddress_RevertWhen_NotGovernor() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Only Controller governor"));
        rm.setDefaultReclaimAddress(reclaimWallet);
    }

    function test_SetDefaultReclaimAddress_SetsDefaultReclaimAddressAsGovernor() public {
        vm.expectEmit(address(rm));
        emit DefaultReclaimAddressSet(address(0), reclaimWallet);
        _setDefaultReclaimAddress(reclaimWallet);

        assertEq(rm.getDefaultReclaimAddress(), reclaimWallet);
    }

    function test_SetDefaultReclaimAddress_AllowsSettingToZeroAddress() public {
        _setDefaultReclaimAddress(reclaimWallet);

        vm.expectEmit(address(rm));
        emit DefaultReclaimAddressSet(reclaimWallet, address(0));
        _setDefaultReclaimAddress(address(0));
    }

    function test_SetDefaultReclaimAddress_NoEventWhenSettingSameAddress() public {
        _setDefaultReclaimAddress(reclaimWallet);

        vm.recordLogs();
        _setDefaultReclaimAddress(reclaimWallet);
        _assertNotEmitted(vm.getRecordedLogs(), DefaultReclaimAddressSet.selector);
    }

    // -- default reclaim address fallback --

    function test_DefaultReclaimAddressFallback_UsesDefaultWhenReasonSpecificNotSet()
        public
        withAllocationAndAvailabilityOracle
    {
        _setDefaultReclaimAddress(reclaimWallet);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = _subgraphRewards(MINED_BLOCKS);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        // Reclaimed to the default address under the SUBGRAPH_DENIED reason
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _triggerAllocationUpdate();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_DefaultReclaimAddressFallback_PrefersReasonSpecificOverDefault()
        public
        withAllocationAndAvailabilityOracle
    {
        _setDefaultReclaimAddress(otherWallet);
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 balanceBefore = token.balanceOf(reclaimWallet);
        uint256 otherBalanceBefore = token.balanceOf(otherWallet);

        _triggerAllocationUpdate();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, _subgraphRewards(MINED_BLOCKS));
        assertEq(token.balanceOf(otherWallet), otherBalanceBefore);
    }

    // -- reclaim NO_SIGNAL - zero total signal --

    function test_ReclaimNoSignalZeroTotalSignal_ReclaimsWhenNoSignalAddressSet() public {
        _setReclaimAddress(RewardsCondition.NO_SIGNAL, reclaimWallet);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = MINED_BLOCKS * ISSUANCE_PER_BLOCK;
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(RewardsCondition.NO_SIGNAL, expectedRewards, address(0), address(0), bytes32(0));
        vm.prank(governor);
        rm.updateAccRewardsPerSignal();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimNoSignalZeroTotalSignal_DropsWhenNoReclaimAddress() public {
        vm.roll(block.number + MINED_BLOCKS);

        vm.recordLogs();
        vm.prank(governor);
        rm.updateAccRewardsPerSignal();
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
    }

    function test_ReclaimNoSignalZeroTotalSignal_UsesDefaultWhenSpecificNotSet() public {
        _setDefaultReclaimAddress(reclaimWallet);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = MINED_BLOCKS * ISSUANCE_PER_BLOCK;
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(RewardsCondition.NO_SIGNAL, expectedRewards, address(0), address(0), bytes32(0));
        vm.prank(governor);
        rm.updateAccRewardsPerSignal();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    // -- reclaim NO_ALLOCATED_TOKENS - signal but no allocations --

    function test_ReclaimNoAllocatedTokensSignalButNoAllocations_ReclaimsWhenNoAllocatedTokensAddressSet() public {
        _setReclaimAddress(RewardsCondition.NO_ALLOCATED_TOKENS, reclaimWallet);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = _subgraphRewards(MINED_BLOCKS);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.NO_ALLOCATED_TOKENS,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _triggerAllocationUpdate();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimNoAllocatedTokensSignalButNoAllocations_DropsWhenNoReclaimAddress() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + MINED_BLOCKS);

        vm.recordLogs();
        _triggerAllocationUpdate();
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
    }

    // -- reclaim BELOW_MINIMUM_SIGNAL --

    function test_ReclaimBelowMinimumSignal_ReclaimsWhenBelowMinimumAddressSet() public withMinimumSignal {
        _setReclaimAddress(RewardsCondition.BELOW_MINIMUM_SIGNAL, reclaimWallet);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, BELOW_MINIMUM);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = _expectedSubgraphRewards(MINED_BLOCKS, BELOW_MINIMUM, BELOW_MINIMUM);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.BELOW_MINIMUM_SIGNAL,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _triggerAllocationUpdate();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    function test_ReclaimBelowMinimumSignal_NoReclaimWhenSignalAtOrAboveMinimum() public withMinimumSignal {
        _setReclaimAddress(RewardsCondition.BELOW_MINIMUM_SIGNAL, reclaimWallet);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, MINIMUM_SIGNAL);
        vm.roll(block.number + 1);
        // An allocation, so rewards accumulate normally
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        vm.roll(block.number + MINED_BLOCKS);

        vm.recordLogs();
        _triggerAllocationUpdate();
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
    }

    function test_ReclaimBelowMinimumSignal_DropsWhenNoReclaimAddress() public withMinimumSignal {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, BELOW_MINIMUM);
        vm.roll(block.number + MINED_BLOCKS);

        vm.recordLogs();
        _triggerAllocationUpdate();
        _assertNotEmitted(vm.getRecordedLogs(), RewardsReclaimed.selector);
    }

    function test_ReclaimBelowMinimumSignal_UsesBelowMinimumWhenDeniedWithoutSubgraphDeniedAddress()
        public
        withMinimumSignal
    {
        _setReclaimAddress(RewardsCondition.BELOW_MINIMUM_SIGNAL, reclaimWallet);
        _deny();
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, BELOW_MINIMUM);
        vm.roll(block.number + MINED_BLOCKS);

        uint256 expectedRewards = _expectedSubgraphRewards(MINED_BLOCKS, BELOW_MINIMUM, BELOW_MINIMUM);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        // Denied, but with no SUBGRAPH_DENIED address the condition falls back to BELOW_MINIMUM_SIGNAL
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.BELOW_MINIMUM_SIGNAL,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _triggerAllocationUpdate();

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, expectedRewards);
    }

    // -- dual denial - SUBGRAPH_DENIED takes precedence when configured --

    function test_DualDenialSubgraphDeniedTakesPrecedenceWhenConfigured_ReclaimsToSubgraphDeniedForPreDenialAllocation()
        public
    {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, otherWallet);
        _setAvailabilityOracle(governor);
        _useEligibilityOracle(false);

        // Allocate first, then deny, so the rewards reach `_deniedRewards`
        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + 1);

        uint256 allocationRewards = _epochAllocationRewards();
        uint256 subgraphLevelRewards = _subgraphRewards(1);
        uint256 subgraphDeniedBalanceBefore = token.balanceOf(reclaimWallet);
        uint256 indexerIneligibleBalanceBefore = token.balanceOf(otherWallet);

        vm.expectEmit(address(rm));
        emit RewardsDenied(indexer, allocationID1);
        vm.expectEmit(address(rm));
        emit RewardsDeniedDueToEligibility(indexer, allocationID1, allocationRewards);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            allocationRewards,
            indexer,
            allocationID1,
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _close(allocationID1);

        // SUBGRAPH_DENIED wallet gets the allocation's rewards plus the subgraph-level block after the denial
        assertGt(token.balanceOf(reclaimWallet) - subgraphDeniedBalanceBefore, 0);
        assertEq(
            token.balanceOf(reclaimWallet) - subgraphDeniedBalanceBefore,
            allocationRewards + subgraphLevelRewards
        );
        assertEq(token.balanceOf(otherWallet), indexerIneligibleBalanceBefore);
    }
}
