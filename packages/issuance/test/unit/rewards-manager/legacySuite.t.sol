// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { RewardsCondition } from "@graphprotocol/interfaces/contracts/contracts/rewards/RewardsCondition.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

/// @notice The cases of the legacy `rewards.test.ts` that no other RewardsManager port covers.
contract RewardsManagerLegacySuiteTest is RewardsManagerSharedTest {
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsDenied(address indexed indexer, address indexed allocationID);
    event RewardsDeniedDueToEligibility(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsReclaimed(
        bytes32 indexed reason,
        uint256 amount,
        address indexed indexer,
        address indexed allocationID,
        bytes32 subgraphDeploymentID
    );

    uint256 internal constant ISSUANCE_RATE_PERIODS = 4;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");
    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_2 = keccak256("subgraphDeploymentID2");

    address internal allocationID1 = makeAddr("allocationID1");
    address internal allocationID2 = makeAddr("allocationID2");
    address internal reclaimWallet = makeAddr("reclaimWallet");

    /// Allocation on a subgraph with no signal, closed one block later: there are no rewards to deny or reclaim.
    /// Legacy Staking closed this under-one-epoch allocation through `onSubgraphAllocationUpdate`, not `takeRewards`,
    /// so both paths are asserted.
    function _allocateWithoutSignalAndClose() internal returns (Vm.Log[] memory logs) {
        vm.roll(block.number + EPOCH_LENGTH);
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        vm.roll(block.number + 1);

        uint256 supplyBefore = token.totalSupply();
        vm.recordLogs();
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID_1);
        assertEq(_close(allocationID1), 0);
        logs = vm.getRecordedLogs();

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(reclaimWallet), 0);
        _assertNotEmitted(logs, RewardsReclaimed.selector);
        _assertNotEmitted(logs, HorizonRewardsAssigned.selector);
    }

    // -- getAccRewardsForSubgraph --

    function test_GetAccRewardsForSubgraph_AccruedProportionallyToSignal() public {
        uint256 signalled1 = 1500 ether;
        uint256 signalled2 = 500 ether;
        uint256 tokensToAllocate = 10_000 ether;

        _signal(SUBGRAPH_DEPLOYMENT_ID_1, signalled1);
        _signal(SUBGRAPH_DEPLOYMENT_ID_2, signalled2);
        vm.roll(block.number + 1);

        // Both subgraphs have an allocation, so their rewards accrue instead of being reclaimed
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, tokensToAllocate);
        _allocate(allocationID2, SUBGRAPH_DEPLOYMENT_ID_2, tokensToAllocate);

        uint256 startRewardsSG1 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1);
        uint256 startRewardsSG2 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_2);

        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        uint256 accruedSG1 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1) - startRewardsSG1;
        uint256 accruedSG2 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_2) - startRewardsSG2;
        uint256 totalAccrued = accruedSG1 + accruedSG2;
        assertGt(totalAccrued, 0, "Should have accrued rewards");

        // SG1 holds 75% of the signal (1500 / 2000), SG2 25%
        assertApproxEqAbs((accruedSG1 * 100) / totalAccrued, 75, 1, "SG1 should have ~75% of rewards");
        assertApproxEqAbs((accruedSG2 * 100) / totalAccrued, 25, 1, "SG2 should have ~25% of rewards");

        uint256 totalSignal = signalled1 + signalled2;
        assertEq(accruedSG1, _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, totalSignal, signalled1));
        assertEq(accruedSG2, _expectedSubgraphRewards(ISSUANCE_RATE_PERIODS, totalSignal, signalled2));
    }

    // -- takeRewards --

    function test_TakeRewards_ZeroRewardsWithDenylistAndReclaimAddress() public {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setAvailabilityOracle(governor);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);

        Vm.Log[] memory logs = _allocateWithoutSignalAndClose();
        _assertNotEmitted(logs, RewardsDenied.selector);
    }

    function test_TakeRewards_ZeroRewardsWithEligibilityOracleAndReclaimAddress() public {
        _setReclaimAddress(RewardsCondition.INDEXER_INELIGIBLE, reclaimWallet);
        _useEligibilityOracle(false);

        Vm.Log[] memory logs = _allocateWithoutSignalAndClose();
        _assertNotEmitted(logs, RewardsDeniedDueToEligibility.selector);
    }

    function test_TakeRewards_CollectsPreDenialRewardsAfterUndeny() public {
        _setAvailabilityOracle(governor);
        uint256 expectedRewards = _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        uint256 rewardsBefore = rm.getRewards(address(issuer), allocationID1);
        assertGt(rewardsBefore, 0);
        assertEq(rewardsBefore, expectedRewards);

        // Denying freezes accRewardsPerAllocatedToken; the denied-period rewards are not the allocation's
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + EPOCH_LENGTH);
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, false);

        uint256 supplyBefore = token.totalSupply();
        uint256 issuerBalanceBefore = token.balanceOf(address(issuer));

        // Closed in the undeny block, so the amount is exactly the frozen pre-denial value
        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, rewardsBefore);
        uint256 rewards = _close(allocationID1);

        assertGt(rewards, 0);
        assertEq(rewards, rewardsBefore);
        assertEq(token.totalSupply(), supplyBefore + rewards);
        assertEq(token.balanceOf(address(issuer)), issuerBalanceBefore + rewards);
    }

    function test_TakeRewards_AllocationCreatedWhileDeniedEarnsOnlyPostUndenyRewards() public {
        _setAvailabilityOracle(governor);

        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + 1);

        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        vm.roll(block.number + EPOCH_LENGTH);

        // Snapshot is the frozen accRewardsPerAllocatedToken
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        vm.roll(block.number + EPOCH_LENGTH);

        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, false);
        vm.roll(block.number + EPOCH_LENGTH);

        // Only the epoch after the undeny counts
        uint256 expectedRewards = _expectedAllocationRewards(EPOCH_LENGTH, ALLOCATION, ALLOCATION);
        uint256 supplyBefore = token.totalSupply();

        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        uint256 rewards = _close(allocationID1);

        assertGt(rewards, 0);
        assertEq(rewards, expectedRewards);
        assertGt(token.totalSupply(), supplyBefore);
        assertEq(token.totalSupply(), supplyBefore + expectedRewards);
    }

    function test_TakeRewards_ReclaimsDeniedPeriodRewardsViaOnSubgraphAllocationUpdate() public {
        _setReclaimAddress(RewardsCondition.SUBGRAPH_DENIED, reclaimWallet);
        _setAvailabilityOracle(governor);

        _allocateAndAccrue(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);

        // Denying distributes the pre-denial rewards to the allocation, then freezes the accumulator
        _setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);
        uint256 balanceBefore = token.balanceOf(reclaimWallet);

        vm.roll(block.number + EPOCH_LENGTH);

        // A second allocation triggers onSubgraphAllocationUpdate, which reclaims the denied period
        uint256 deniedPeriodRewards = _subgraphRewards(EPOCH_LENGTH);
        vm.expectEmit(address(rm));
        emit RewardsReclaimed(
            RewardsCondition.SUBGRAPH_DENIED,
            deniedPeriodRewards,
            address(0),
            address(0),
            SUBGRAPH_DEPLOYMENT_ID_1
        );
        _allocate(allocationID2, SUBGRAPH_DEPLOYMENT_ID_1, 5000 ether);

        assertGt(token.balanceOf(reclaimWallet), balanceBefore);
        assertEq(token.balanceOf(reclaimWallet) - balanceBefore, deniedPeriodRewards);
    }
}
