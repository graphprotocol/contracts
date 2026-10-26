// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerDistributionTest is RewardsManagerSharedTest {
    event HorizonRewardsAssigned(address indexed indexer, address indexed allocationID, uint256 amount);
    event RewardsDenied(address indexed indexer, address indexed allocationID);
    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 internal constant ISSUANCE_RATE_PERIODS = 4;

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");
    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_2 = keccak256("subgraphDeploymentID2");

    address internal allocationID1 = makeAddr("allocationID1");
    address internal allocationID2 = makeAddr("allocationID2");
    address internal allocationIDNull = makeAddr("allocationIDNull");

    /// Signal, then allocate one block later, so the pre-allocation block is reclaimed (NO_ALLOCATED_TOKENS).
    function _setupIndexerAllocation() internal {
        _signalThenAllocate(SUBGRAPH_DEPLOYMENT_ID_1, allocationID1);
    }

    function _setupIndexerAllocationSignalingAfter() internal {
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        vm.roll(block.number + 1);
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
    }

    /// RewardsManager half of the legacy-Staking close cases: event amount, mint to the issuer and total supply.
    function _assertRewardsDistributedOnClose() internal {
        // All the subgraph's rewards since the allocation go to it
        uint256 expectedIndexingRewards = _expectedAllocationRewards(EPOCH_LENGTH, ALLOCATION, ALLOCATION);
        uint256 beforeTokenSupply = token.totalSupply();
        uint256 beforeIssuerBalance = token.balanceOf(address(issuer));

        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedIndexingRewards);
        uint256 rewards = _close(allocationID1);

        assertEq(rewards, expectedIndexingRewards);
        assertEq(token.balanceOf(address(issuer)), beforeIssuerBalance + expectedIndexingRewards);
        assertEq(token.totalSupply(), beforeTokenSupply + expectedIndexingRewards);
    }

    // -- getRewards --

    function test_GetRewards_UsesSignalledAndAllocatedTokens() public {
        _setupIndexerAllocation();
        vm.roll(block.number + ISSUANCE_RATE_PERIODS);

        uint256 rewards = rm.getRewards(address(issuer), allocationID1);

        (uint256 accRewardsPerAllocatedToken, ) = rm.getAccRewardsPerAllocatedToken(SUBGRAPH_DEPLOYMENT_ID_1);
        assertEq(rewards, (accRewardsPerAllocatedToken * ALLOCATION) / 1e18);
        assertEq(rewards, _expectedAllocationRewards(ISSUANCE_RATE_PERIODS, ALLOCATION, ALLOCATION));
    }

    function test_GetRewards_ZeroWhenAllocationClosed() public {
        _setupIndexerAllocation();
        vm.roll(block.number + ISSUANCE_RATE_PERIODS + EPOCH_LENGTH);

        _close(allocationID1);

        assertEq(rm.getRewards(address(issuer), allocationID1), 0);
    }

    function test_GetRewards_ZeroWhenAllocationDoesNotExist() public view {
        assertEq(rm.getRewards(address(issuer), allocationIDNull), 0);
    }

    // -- takeRewards --

    function test_TakeRewards_DistributesOnClosedAllocationAndStake() public {
        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        _assertRewardsDistributedOnClose();
    }

    function test_TakeRewards_NoUnderflowWhenMinimumSignalChanges() public {
        _setupIndexerAllocation();

        vm.prank(governor);
        rm.setMinimumSubgraphSignal(14_000 ether);

        vm.roll(block.number + EPOCH_LENGTH);

        vm.recordLogs();
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);
    }

    function test_TakeRewards_NoUnderflowWhenMinimumSignalChangesAndSignalAfterAllocation() public {
        _setupIndexerAllocationSignalingAfter();

        vm.prank(governor);
        rm.setMinimumSubgraphSignal(14_000 ether);

        vm.roll(block.number + EPOCH_LENGTH);

        vm.recordLogs();
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);
    }

    function test_TakeRewards_NoRevertWhenSignalAlreadyUnderMinimum() public {
        vm.prank(governor);
        rm.setMinimumSubgraphSignal(2000 ether);

        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        vm.recordLogs();
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);
    }

    function test_TakeRewards_DistributesOnClosedAllocationToDestination() public {
        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        _assertRewardsDistributedOnClose();
    }

    function test_TakeRewards_DistributesOnClosedAllocationWithDelegators() public {
        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        _assertRewardsDistributedOnClose();
    }

    function test_TakeRewards_DeniesRewardsWhenSubgraphDenied() public {
        vm.prank(governor);
        rm.setSubgraphAvailabilityOracle(governor);

        // Allocation created before the subgraph is denied
        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        vm.prank(governor);
        rm.setDenied(SUBGRAPH_DEPLOYMENT_ID_1, true);

        vm.expectEmit(address(rm));
        emit RewardsDenied(indexer, allocationID1);
        _close(allocationID1);
    }

    function test_TakeRewards_ZeroRewards() public {
        vm.prank(governor);
        rm.setIssuancePerBlock(0);

        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        uint256 beforeTokenSupply = token.totalSupply();
        uint256 beforeIssuerBalance = token.balanceOf(address(issuer));

        vm.recordLogs();
        _close(allocationID1);
        _assertNotEmitted(vm.getRecordedLogs(), HorizonRewardsAssigned.selector);

        assertEq(token.totalSupply(), beforeTokenSupply);
        assertEq(token.balanceOf(address(issuer)), beforeIssuerBalance);
    }

    // -- edge scenarios --

    function test_EdgeScenarios_CloseAllocationOnSubgraphWithNoSignal() public {
        _setupIndexerAllocation();
        vm.roll(block.number + EPOCH_LENGTH);

        curation.unsignal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + 1);

        // Must not revert
        _close(allocationID1);
    }

    // -- multiple allocations --

    function test_MultipleAllocations_SameBlockWithGrtBurnInTheMiddle() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + 1);

        uint256 tokensToAlloc = 5000 ether;

        // No vm.roll between the three calls: they run in the same block
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, tokensToAlloc);
        vm.expectEmit(address(token));
        emit Transfer(address(this), address(0), 1 ether);
        token.burn(1 ether);
        _allocate(allocationID2, SUBGRAPH_DEPLOYMENT_ID_1, tokensToAlloc);

        (bool isActive1, , , , , ) = issuer.getAllocationData(allocationID1);
        (bool isActive2, , , , , ) = issuer.getAllocationData(allocationID2);
        assertTrue(isActive1);
        assertTrue(isActive2);
        assertEq(issuer.getSubgraphAllocatedTokens(SUBGRAPH_DEPLOYMENT_ID_1), 2 * tokensToAlloc);
    }

    function test_MultipleAllocations_SimultaneousSimilarAllocationsGetSameRewards() public {
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        vm.roll(block.number + 1);

        uint256 tokensToAlloc = 5000 ether;
        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, tokensToAlloc);
        _allocate(allocationID2, SUBGRAPH_DEPLOYMENT_ID_1, tokensToAlloc);

        vm.roll(block.number + EPOCH_LENGTH);

        uint256 expectedRewards = _expectedAllocationRewards(EPOCH_LENGTH, tokensToAlloc, 2 * tokensToAlloc);

        // Closed in the same block
        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID1, expectedRewards);
        uint256 rewards1 = _close(allocationID1);
        vm.expectEmit(address(rm));
        emit HorizonRewardsAssigned(indexer, allocationID2, expectedRewards);
        uint256 rewards2 = _close(allocationID2);

        assertEq(rewards1, rewards2);
    }

    // -- rewards progression when collecting query fees --

    function test_RewardsProgressionWhenCollectingQueryFees_TwoSubgraphsOneAllocation() public {
        uint256 curationFees = 1_000 ether; // 10% curation share of 10,000 GRT collected

        // Signal in two subgraphs in the same block
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, SIGNAL);
        _signal(SUBGRAPH_DEPLOYMENT_ID_2, SIGNAL);
        vm.roll(block.number + 1);

        _allocate(allocationID1, SUBGRAPH_DEPLOYMENT_ID_1, ALLOCATION);
        uint256 b1 = block.number;

        vm.roll(block.number + EPOCH_LENGTH);

        curation.addFees(SUBGRAPH_DEPLOYMENT_ID_1, curationFees);

        vm.roll(block.number + 1);
        uint256 accrualSG1 = rm.getAccRewardsForSubgraph(SUBGRAPH_DEPLOYMENT_ID_1);
        uint256 b2 = block.number;

        // Fees reach Curation without a RewardsManager hook, so the view prices every block since the
        // allocation at the current signal: SG1's pool and the total both include the fees
        assertEq(accrualSG1, _expectedSubgraphRewards(b2 - b1, 2 * SIGNAL + curationFees, SIGNAL + curationFees));
    }
}
