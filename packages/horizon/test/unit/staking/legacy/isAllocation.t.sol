// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IHorizonStakingTypes } from "@graphprotocol/interfaces/contracts/horizon/internal/IHorizonStakingTypes.sol";
import { HorizonStakingSharedTest } from "../../shared/horizon-staking/HorizonStakingShared.t.sol";

contract HorizonStakingIsAllocationTest is HorizonStakingSharedTest {
    /*
     * TESTS
     */

    function test_IsAllocation_ReturnsFalse_WhenAllocationDoesNotExist() public {
        address nonExistentAllocationId = makeAddr("nonExistentAllocation");
        assertFalse(staking.isAllocation(nonExistentAllocationId));
    }

    function test_IsAllocation_ReturnsTrue_WhenActiveAllocationExists() public {
        address allocationId = makeAddr("activeAllocation");

        // Set up an active legacy allocation in storage
        _setLegacyAllocationInStaking(
            allocationId,
            users.indexer,
            bytes32("subgraphDeploymentId"),
            1000 ether, // tokens
            1, // createdAtEpoch
            0 // closedAtEpoch (0 = still active)
        );

        assertTrue(staking.isAllocation(allocationId));
    }

    function test_IsAllocation_ReturnsTrue_WhenClosedAllocationExists() public {
        address allocationId = makeAddr("closedAllocation");

        // Set up a closed legacy allocation in storage
        _setLegacyAllocationInStaking(
            allocationId,
            users.indexer,
            bytes32("subgraphDeploymentId"),
            1000 ether, // tokens
            1, // createdAtEpoch
            10 // closedAtEpoch (non-zero = closed)
        );

        assertTrue(staking.isAllocation(allocationId));
    }

    function test_IsAllocation_ReturnsFalse_WhenIndexerIsZeroAddress() public {
        address allocationId = makeAddr("zeroIndexerAllocation");

        // Set up an allocation with zero indexer (should be considered Null)
        _setLegacyAllocationInStaking(
            allocationId,
            address(0), // indexer is zero
            bytes32("subgraphDeploymentId"),
            1000 ether,
            1,
            0
        );

        assertFalse(staking.isAllocation(allocationId));
    }

    /*
     * HELPERS
     */

    /**
     * @notice Sets a legacy allocation directly in HorizonStaking storage
     * @dev The __DEPRECATED_allocations mapping is at storage slot 10 in HorizonStakingStorage
     * The LegacyAllocation struct has the following layout:
     * - slot 0: indexer (address)
     * - slot 1: subgraphDeploymentID (bytes32)
     * - slot 2: tokens (uint256)
     * - slot 3: createdAtEpoch (uint256)
     * - slot 4: closedAtEpoch (uint256)
     * - slot 5: collectedFees (uint256)
     * - slot 6: __DEPRECATED_effectiveAllocation (uint256)
     * - slot 7: accRewardsPerAllocatedToken (uint256)
     * - slot 8: distributedRebates (uint256)
     */
    function _setLegacyAllocationInStaking(
        address _allocationId,
        address _indexer,
        bytes32 _subgraphDeploymentId,
        uint256 _tokens,
        uint256 _createdAtEpoch,
        uint256 _closedAtEpoch
    ) internal {
        // Storage slot for __DEPRECATED_allocations mapping in HorizonStaking
        // Use `forge inspect HorizonStaking storage-layout` to verify
        uint256 allocationsSlot = 15;
        bytes32 allocationBaseSlot = keccak256(abi.encode(_allocationId, allocationsSlot));

        // Set indexer (slot 0)
        vm.store(address(staking), allocationBaseSlot, bytes32(uint256(uint160(_indexer))));
        // Set subgraphDeploymentID (slot 1)
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 1), _subgraphDeploymentId);
        // Set tokens (slot 2)
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 2), bytes32(_tokens));
        // Set createdAtEpoch (slot 3)
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 3), bytes32(_createdAtEpoch));
        // Set closedAtEpoch (slot 4)
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 4), bytes32(_closedAtEpoch));
    }
}
