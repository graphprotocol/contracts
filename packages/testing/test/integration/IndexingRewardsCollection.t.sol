// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAllocation } from "@graphprotocol/interfaces/contracts/subgraph-service/internal/IAllocation.sol";
import { Allocation } from "subgraph-service/libraries/Allocation.sol";

import { RealRewardsHarness } from "../harness/RealRewardsHarness.t.sol";

/// @title IndexingRewardsCollectionTest
/// @notice Integration tests for indexing-reward collection accounting, exercised end-to-end
///         against the **real production RewardsManager** (via RealRewardsHarness) so the reward
///         math is the genuine on-chain implementation rather than a mock.
///
/// Core property under test: an indexer is paid each accrual period exactly once — including when
/// presenting a POI while over-allocated, which auto-downsizes the allocation to zero tokens while
/// keeping it open as a (now zero-token) rewards target.
contract IndexingRewardsCollectionTest is RealRewardsHarness {
    using Allocation for IAllocation.State;

    bytes32 internal constant SUBGRAPH = keccak256("indexing-rewards-subgraph");

    /// @notice Collecting while over-allocated pays the accrued reward once: the allocation is
    ///         downsized to zero tokens but stays open, no pending reward is left behind, and a
    ///         further collection on the zero-token allocation pays nothing.
    function test_Collect_Indexing_OverAllocated_PaysEachAccrualOnce() public {
        if (!realRmAvailable) {
            emit log(
                string.concat(
                    "SKIP: RewardsManager artifact not found at ",
                    RM_ARTIFACT,
                    " (build the contracts package first)"
                )
            );
            vm.skip(true);
            return;
        }

        IndexerSetup memory ix = _setupIndexer("indexer", SUBGRAPH, MINIMUM_PROVISION_TOKENS * 100);

        // Thaw half the provision so the allocated tokens exceed the available provision: the
        // indexer is now over-allocated and the next POI will trigger the auto-downsize path.
        vm.prank(ix.addr);
        staking.thaw(ix.addr, address(subgraphService), ix.provisionTokens / 2);

        vm.roll(block.number + 100); // let rewards accrue over 100 blocks

        bytes memory collectData = abi.encode(ix.allocationId, bytes32("POI"), _poiMetadata());

        // Collect the accrued reward. Over-allocation downsizes the allocation to zero tokens.
        uint256 supplyBefore = token.totalSupply();
        vm.prank(ix.addr);
        subgraphService.collect(ix.addr, IGraphPayments.PaymentTypes.IndexingRewards, collectData);
        uint256 firstReward = token.totalSupply() - supplyBefore;
        assertGt(firstReward, 0, "accrued indexing reward is minted on collection");

        // The downsized allocation stays open as a valid (zero-token) rewards target, and the
        // reward just paid leaves nothing collectable behind.
        IAllocation.State memory alloc = subgraphService.getAllocation(ix.allocationId);
        assertEq(alloc.tokens, 0, "over-allocation downsizes the allocation to zero tokens");
        assertEq(alloc.closedAt, 0, "downsized allocation remains open");
        assertTrue(alloc.isOpen(), "downsized allocation is still a valid rewards target");
        assertFalse(alloc.isStale(MAX_POI_STALENESS), "collection took the active-rewards path, not stale-reclaim");
        assertEq(alloc.accRewardsPending, 0, "a collected accrual leaves no pending rewards");

        // A second collection over the same (now zero-token) allocation, with no further accrual,
        // pays nothing: each accrual is paid exactly once.
        vm.prank(ix.addr);
        subgraphService.collect(ix.addr, IGraphPayments.PaymentTypes.IndexingRewards, collectData);
        uint256 secondReward = token.totalSupply() - supplyBefore - firstReward;
        assertEq(secondReward, 0, "a zero-token allocation accrues and pays no further rewards");
    }

    function _poiMetadata() internal view returns (bytes memory) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encode(block.number, bytes32("PUBLIC_POI"), uint8(0), uint8(0), uint256(0));
    }
}
