// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { HorizonStakingTest } from "../HorizonStaking.t.sol";
import { IHorizonStakingExtension } from "../../../contracts/interfaces/internal/IHorizonStakingExtension.sol";

contract HorizonStakingExtensionTest is HorizonStakingTest {

    /*
     * VARIABLES
     */

    address internal _allocationId = makeAddr("allocationId");
    bytes32 internal constant _subgraphDeploymentID = keccak256("subgraphDeploymentID");
    bytes32 internal constant _poi = keccak256("poi");
    uint256 internal constant MAX_ALLOCATION_EPOCHS = 28;
    IHorizonStakingExtension.Allocation internal _allocation;

    /*
     * MODIFIERS
     */

    modifier useAllocation() {
        _storeAllocation(0);
        _;
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();

        _allocation = IHorizonStakingExtension.Allocation({
            indexer: users.indexer,
            subgraphDeploymentID: _subgraphDeploymentID,
            tokens: 0,
            createdAtEpoch: block.timestamp,
            closedAtEpoch: 0,
            collectedFees: 0,
            __DEPRECATED_effectiveAllocation: 0,
            accRewardsPerAllocatedToken: 0,
            distributedRebates: 0
        });
    }

    /*
     * HELPERS
     */

    function _storeAllocation(uint256 tokens) internal {
        uint256 allocationsSlot = 15;
        bytes32 allocationBaseSlot = keccak256(abi.encode(_allocationId, allocationsSlot));
        vm.store(address(staking), allocationBaseSlot, bytes32(uint256(uint160(_allocation.indexer))));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 1), _allocation.subgraphDeploymentID);
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 2), bytes32(tokens));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 3), bytes32(_allocation.createdAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 4), bytes32(_allocation.closedAtEpoch));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 5), bytes32(_allocation.collectedFees));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 6), bytes32(_allocation.__DEPRECATED_effectiveAllocation));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 7), bytes32(_allocation.accRewardsPerAllocatedToken));
        vm.store(address(staking), bytes32(uint256(allocationBaseSlot) + 8), bytes32(_allocation.distributedRebates));

        uint256 serviceProviderSlot = 14;
        bytes32 serviceProviderBaseSlot = keccak256(abi.encode(_allocation.indexer, serviceProviderSlot));
        vm.store(address(staking), bytes32(uint256(serviceProviderBaseSlot) + 1), bytes32(tokens));

        uint256 subgraphsAllocationsSlot = 16;
        bytes32 subgraphAllocationsBaseSlot = keccak256(abi.encode(_allocation.subgraphDeploymentID, subgraphsAllocationsSlot));
        vm.store(address(staking), subgraphAllocationsBaseSlot, bytes32(tokens));
    }

    function _storeMaxAllocationEpochs() internal {
        uint256 slot = 13;
        vm.store(address(staking), bytes32(slot), bytes32(MAX_ALLOCATION_EPOCHS) << 128);
    }

    function _storeRewardsDestination(address destination) internal {
        uint256 rewardsDestinationSlot = 23;
        bytes32 rewardsDestinationSlotBaseSlot = keccak256(abi.encode(users.indexer, rewardsDestinationSlot));
        vm.store(address(staking), rewardsDestinationSlotBaseSlot, bytes32(uint256(uint160(destination))));
    }
}