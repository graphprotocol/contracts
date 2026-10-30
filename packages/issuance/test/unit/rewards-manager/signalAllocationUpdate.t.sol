// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

/// Signal/allocation update accounting: when `onSubgraphSignalUpdate` runs before `onSubgraphAllocationUpdate`
/// in the same block, the per-signal delta of the second call is zero, and rewards already tracked in
/// `accRewardsForSubgraph` must still reach allocations. Hardhat's batched (automine off) blocks are
/// consecutive calls with no `vm.roll` in between.
contract RewardsManagerSignalAllocationUpdateTest is RewardsManagerSharedTest {
    event RewardsReclaimed(
        bytes32 indexed reason,
        uint256 amount,
        address indexed indexer,
        address indexed allocationID,
        bytes32 subgraphDeploymentID
    );

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID = keccak256("subgraphDeploymentID");

    address internal allocationID = makeAddr("allocationID");
    address internal reclaimWallet = makeAddr("reclaimWallet");

    // -- Helpers --

    function _setupSubgraphWithAllocation() internal {
        _signalThenAllocate(SUBGRAPH_DEPLOYMENT_ID, allocationID);
    }

    function _deny() internal {
        vm.startPrank(governor);
        rm.setSubgraphAvailabilityOracle(governor);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID, true);
        vm.stopPrank();
    }

    function _perAllocatedToken(uint256 blocks) internal pure returns (uint256) {
        return _expectedRewardsPerAllocatedToken(_subgraphRewards(blocks), ALLOCATION);
    }

    // -- onSubgraphSignalUpdate followed by onSubgraphAllocationUpdate --

    function test_OnSubgraphSignalUpdateFollowedByOnSubgraphAllocationUpdate_DistributesWhenSignalUpdatePrecedesSameBlock()
        public
    {
        _setupSubgraphWithAllocation();
        vm.roll(block.number + 100);

        uint256 expectedRewardsForSubgraph = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertGt(expectedRewardsForSubgraph, 0);
        assertEq(expectedRewardsForSubgraph, _subgraphRewards(100));
        uint256 accRewardsPerAllocatedTokenBefore = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken;

        // Same block: no vm.roll between the two hooks
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertGt(sg.accRewardsForSubgraph, 0);
        assertEq(sg.accRewardsForSubgraph, expectedRewardsForSubgraph);
        assertGt(sg.accRewardsPerAllocatedToken, accRewardsPerAllocatedTokenBefore);
        assertEq(sg.accRewardsPerAllocatedToken, accRewardsPerAllocatedTokenBefore + _perAllocatedToken(100));
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
    }

    function test_OnSubgraphSignalUpdateFollowedByOnSubgraphAllocationUpdate_DoesNotBrickRewardsWhenPerSignalDeltaIsZero()
        public
    {
        _setupSubgraphWithAllocation();
        vm.roll(block.number + 100);

        rm.getAccRewardsPerAllocatedToken(SUBGRAPH_DEPLOYMENT_ID);

        // Same block: no vm.roll between the two hooks
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertGt(sg.accRewardsForSubgraph, 0);
        assertEq(sg.accRewardsForSubgraph, _subgraphRewards(100));
        assertGt(sg.accRewardsPerAllocatedToken, 0);
        assertEq(sg.accRewardsPerAllocatedToken, _perAllocatedToken(100));

        (uint256 viewAccRewardsPerAllocatedToken, ) = rm.getAccRewardsPerAllocatedToken(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(viewAccRewardsPerAllocatedToken, sg.accRewardsPerAllocatedToken);
    }

    function test_OnSubgraphSignalUpdateFollowedByOnSubgraphAllocationUpdate_MultipleSignalUpdatesDoNotLoseRewards()
        public
    {
        _setupSubgraphWithAllocation();
        vm.roll(block.number + 50);

        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory afterFirstSignal = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterFirstSignal.accRewardsForSubgraph, _subgraphRewards(50));

        vm.roll(block.number + 50);

        // Same block: no vm.roll between the two hooks
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertGt(sg.accRewardsForSubgraph, afterFirstSignal.accRewardsForSubgraph);
        assertEq(sg.accRewardsForSubgraph, 2 * _subgraphRewards(50));
        assertGt(sg.accRewardsPerAllocatedToken, 0);
        assertEq(sg.accRewardsPerAllocatedToken, 2 * _perAllocatedToken(50));
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
    }

    // -- snapshot consistency in reclaim paths --

    function test_SnapshotConsistencyInReclaimPaths_UpdatesSnapshotWhenReclaimedDueToDenial() public {
        _setupSubgraphWithAllocation();
        // Deny in the next block, as the separate Hardhat transactions: that block is distributed first
        vm.roll(block.number + 1);
        _deny();

        vm.roll(block.number + 100);

        IRewardsManager.Subgraph memory before = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        assertEq(sg.accRewardsPerAllocatedToken, before.accRewardsPerAllocatedToken);
        assertGe(sg.accRewardsForSubgraphSnapshot, before.accRewardsForSubgraphSnapshot);
        // The accumulator stays frozen at the pre-denial block, the snapshot stays synced with it, and the
        // per-signal snapshot moves to now, so the reclaimed period cannot be processed again
        assertEq(sg.accRewardsForSubgraph, _subgraphRewards(1));
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
        assertEq(sg.accRewardsPerSignalSnapshot, rm.accRewardsPerSignal());
        assertGt(sg.accRewardsPerSignalSnapshot, before.accRewardsPerSignalSnapshot);
    }

    function test_SnapshotConsistencyInReclaimPaths_NoDoubleReclaimAfterSnapshotUpdate() public {
        _setupSubgraphWithAllocation();
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _deny();

        vm.roll(block.number + 100);

        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory afterFirstReclaim = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(token.balanceOf(reclaimWallet), _subgraphRewards(100));

        // The next Hardhat transaction: one more block
        vm.roll(block.number + 1);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory afterSecondReclaim = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        uint256 maxOneBlockReward = (ISSUANCE_PER_BLOCK * SIGNAL) / token.balanceOf(address(curation));
        uint256 snapshotDiff = afterSecondReclaim.accRewardsForSubgraphSnapshot -
            afterFirstReclaim.accRewardsForSubgraphSnapshot;
        assertLe(snapshotDiff, 2 * maxOneBlockReward);
        assertEq(snapshotDiff, 0);
        // Only the new block is reclaimed the second time
        assertEq(token.balanceOf(reclaimWallet), _subgraphRewards(100) + _subgraphRewards(1));
        assertEq(afterSecondReclaim.accRewardsPerAllocatedToken, afterFirstReclaim.accRewardsPerAllocatedToken);
    }

    // -- onSubgraphSignalUpdate on denied subgraph --

    function test_OnSubgraphSignalUpdateOnDeniedSubgraph_ReclaimsRewards() public {
        _setupSubgraphWithAllocation();
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        assertEq(rm.getReclaimAddress(RewardsCondition.SUBGRAPH_DENIED), reclaimWallet);

        // Deny in the next block, as the separate Hardhat transactions: that block is distributed first
        vm.roll(block.number + 1);
        _deny();
        IRewardsManager.Subgraph memory afterDenial = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(afterDenial.accRewardsForSubgraph, _subgraphRewards(1));

        vm.roll(block.number + 100);

        uint256 expectedRewards = _subgraphRewards(100);
        assertGt(expectedRewards, 0);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID
        );
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        assertEq(_subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsForSubgraph, afterDenial.accRewardsForSubgraph);
        assertEq(token.balanceOf(reclaimWallet), expectedRewards);
    }

    function test_OnSubgraphSignalUpdateOnDeniedSubgraph_AccumulatesRewardsForClaimableSubgraph() public {
        _setupSubgraphWithAllocation();
        IRewardsManager.Subgraph memory initialState = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        vm.roll(block.number + 100);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        uint256 accRewardsForSubgraph = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsForSubgraph;
        assertGt(accRewardsForSubgraph, initialState.accRewardsForSubgraph);
        assertEq(accRewardsForSubgraph, initialState.accRewardsForSubgraph + _subgraphRewards(100));
    }

    function test_OnSubgraphSignalUpdateOnDeniedSubgraph_ViewDoesNotJumpDuringDenial() public {
        _setupSubgraphWithAllocation();
        vm.roll(block.number + 50);

        // setDenied distributes the pre-denial rewards through onSubgraphAllocationUpdate
        _deny();

        uint256 rewardsAtDenial = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertGt(rewardsAtDenial, 0);
        assertEq(rewardsAtDenial, _subgraphRewards(50));

        vm.roll(block.number + 100);
        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID), rewardsAtDenial);

        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID), rewardsAtDenial);

        vm.roll(block.number + 50);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID), rewardsAtDenial);
    }

    // -- onSubgraphSignalUpdate with no allocations --

    function test_OnSubgraphSignalUpdateWithNoAllocations_ReclaimsAsNoAllocatedTokens() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID, SIGNAL);
        _setReclaimAddress(RewardsCondition.NO_ALLOCATED_TOKENS, reclaimWallet);
        IRewardsManager.Subgraph memory initialState = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        vm.roll(block.number + 100);

        uint256 expectedRewards = _subgraphRewards(100);
        assertGt(expectedRewards, 0);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.NO_ALLOCATED_TOKENS,
            expectedRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID
        );
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        assertEq(_subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsForSubgraph, initialState.accRewardsForSubgraph);
        assertEq(token.balanceOf(reclaimWallet), expectedRewards);
    }

    function test_OnSubgraphSignalUpdateWithNoAllocations_ViewShowsNoPhantomRewards() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID, SIGNAL);
        uint256 viewAfterSignal = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID);

        vm.roll(block.number + 100);

        _setReclaimAddress(RewardsCondition.NO_ALLOCATED_TOKENS, reclaimWallet);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID), viewAfterSignal);
        assertEq(viewAfterSignal, 0);
        // The 100 blocks went to the reclaim address instead
        assertEq(token.balanceOf(reclaimWallet), _subgraphRewards(100));
    }

    // -- invariant: no rewards lost or double-counted --

    function test_InvariantNoRewardsLostOrDoubleCounted_MixedUpdatesWithSameBlockScenarios() public {
        _setupSubgraphWithAllocation();
        vm.roll(block.number + 25);

        // Same block: signal update, then allocation update
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        vm.roll(block.number + 25);

        // Same block: two signal updates, then allocation update
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
        assertGt(sg.accRewardsPerAllocatedToken, 0);
        // Each 25-block period is counted exactly once, whatever the call ordering
        assertEq(sg.accRewardsForSubgraph, 2 * _subgraphRewards(25));
        assertEq(sg.accRewardsPerAllocatedToken, 2 * _perAllocatedToken(25));
        uint256 allocationRewards = rm.getRewards(address(issuer), allocationID);
        assertEq(allocationRewards, (sg.accRewardsPerAllocatedToken * ALLOCATION) / 1e18);
        assertLe(allocationRewards, sg.accRewardsForSubgraph);
    }
}
