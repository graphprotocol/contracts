// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerCalculationsTest is RewardsManagerSharedTest {
    uint256 internal constant ISSUANCE_RATE_PERIODS = 4;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");
    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_2 = keccak256("subgraphDeploymentID2");

    address internal allocationID1 = makeAddr("allocationID1");
    address internal allocationID2 = makeAddr("allocationID2");
    address internal indexer2 = makeAddr("indexer2");

    /// Signal, then allocate one block later, so the pre-allocation block is reclaimed (NO_ALLOCATED_TOKENS).
    function _signalAndAllocate() internal {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + 1);
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
    }

    // -- Review Focus 4: same-block semantics --

    function test_Rewards_ZeroWhenNoBlocksElapsed() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        rm.updateAccRewardsPerSignal();
        uint256 first = rm.accRewardsPerSignal();
        assertEq(first, _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, 1000 ether));

        rm.updateAccRewardsPerSignal();
        assertEq(rm.accRewardsPerSignal(), first);
        assertEq(rm.getNewRewardsPerSignal(), 0);
    }

    // -- getNewRewardsPerSignal --

    function test_GetNewRewardsPerSignal_ZeroWhenNoTokensSignalled() public {
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);
        assertEq(rm.getNewRewardsPerSignal(), 0);
    }

    function test_GetNewRewardsPerSignal_AccruedWhenTokensSignalled() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);
        assertEq(rm.getNewRewardsPerSignal(), _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, 1000 ether));
    }

    function test_GetNewRewardsPerSignal_AccruedWithManySubgraphs() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);
        assertEq(rm.getNewRewardsPerSignal(), _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, 1000 ether));

        // The signal hook brings accRewardsPerSignal up to date, so new rewards restart from here
        _signal(SUBGRAPH_DEPLOYMENT_ID_2, 250 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);
        assertEq(rm.getNewRewardsPerSignal(), _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, 1250 ether));
    }

    // -- updateAccRewardsPerSignal --

    function test_UpdateAccRewardsPerSignal_UpdatesState() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + 1);

        vm.prank(governor);
        rm.updateAccRewardsPerSignal();
        assertEq(rm.accRewardsPerSignal(), _expectedRewardsPerSignal(1, 1000 ether));
    }

    function test_UpdateAccRewardsPerSignal_UpdatesStateAfterManyBlocks() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        vm.prank(governor);
        rm.updateAccRewardsPerSignal();
        assertEq(rm.accRewardsPerSignal(), _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, 1000 ether));
    }

    // -- getAccRewardsForSubgraph --

    function test_GetAccRewardsForSubgraph_AccruedForEachSubgraph() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _signal(SUBGRAPH_DEPLOYMENT_ID_2, 500 ether);

        // SG1's allocation is created a block before SG2's
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        vm.roll(block.number + 1);
        issuer.allocate(allocationID2, indexer2, SUBGRAPH_DEPLOYMENT_ID_2, ALLOCATION);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        uint256 rewardsSG1 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1);
        uint256 rewardsSG2 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_2);
        assertGt(rewardsSG1, 0);
        assertGt(rewardsSG2, 0);
        assertGt(rewardsSG1, rewardsSG2);
    }

    function test_GetAccRewardsForSubgraph_ZeroWhenSignalBelowMinimum() public {
        vm.prank(governor);
        rm.setMinimumSubgraphSignal(2000 ether);

        _signal(SUBGRAPH_DEPLOYMENT_ID_1, 1000 ether);
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1), 0);
    }

    // -- onSubgraphSignalUpdate --

    function test_OnSubgraphSignalUpdate_UpdatesAccRewardsForSubgraph() public {
        _signalAndAllocate();
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        vm.prank(governor);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID_1);

        // Only the blocks since the allocation count for the subgraph; the block before it was reclaimed
        (uint256 accRewardsForSubgraph, , , ) = rm.subgraphs(SUBGRAPH_DEPLOYMENT_ID_1);
        assertEq(accRewardsForSubgraph, _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, SIGNAL, SIGNAL));

        // accRewardsPerSignal is global and accrues from the signal block, in two updates (allocation, then hook)
        assertEq(
            rm.accRewardsPerSignal(),
            _expectedRewardsPerSignal(1, SIGNAL) + _expectedRewardsPerSignal(ISSUANCE_RATE_PERIODS, SIGNAL)
        );
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);
    }

    // -- getAccRewardsPerAllocatedToken --

    function test_GetAccRewardsPerAllocatedToken_AccruedPerAllocatedToken() public {
        _signalAndAllocate();
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        (, uint256 accRewardsForSubgraphSnapshot, , ) = rm.subgraphs(SUBGRAPH_DEPLOYMENT_ID_1);
        uint256 accruedRewardsSG1 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1) -
            accRewardsForSubgraphSnapshot;
        assertEq(accruedRewardsSG1, _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, SIGNAL, SIGNAL));

        (uint256 rewardsPerAllocatedToken, ) = rm.getAccRewardsPerAllocatedToken(SUBGRAPH_DEPLOYMENT_ID_1);
        assertEq(rewardsPerAllocatedToken, _expectedRewardsPerAllocatedToken(accruedRewardsSG1, ALLOCATION));
    }

    // -- onSubgraphAllocationUpdate --

    function test_OnSubgraphAllocationUpdate_UpdatesAccRewardsPerAllocatedToken() public {
        _signalAndAllocate();
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        // Only distributable rewards (blocks since the allocation) count; the block before it was reclaimed
        uint256 expectedSubgraphRewards = _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, SIGNAL, SIGNAL);
        uint256 expectedRewardsPerAllocatedToken = _expectedRewardsPerAllocatedToken(
            expectedSubgraphRewards,
            ALLOCATION
        );

        vm.prank(governor);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID_1);

        (, , , uint256 accRewardsPerAllocatedToken) = rm.subgraphs(SUBGRAPH_DEPLOYMENT_ID_1);
        assertEq(rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1), expectedSubgraphRewards);
        assertEq(accRewardsPerAllocatedToken, expectedRewardsPerAllocatedToken);
    }
}
