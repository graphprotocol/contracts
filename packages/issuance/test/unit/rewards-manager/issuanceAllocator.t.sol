// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";

import { MockERC165 } from "../../../contracts/test/allocate/MockERC165.sol";
import { RewardsManagerSharedTest } from "./shared.t.sol";

contract RewardsManagerIssuanceAllocatorTest is RewardsManagerSharedTest {
    event IssuanceAllocatorSet(
        IIssuanceAllocationDistribution indexed oldIssuanceAllocator,
        IIssuanceAllocationDistribution indexed newIssuanceAllocator
    );

    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID_1 = keccak256("subgraphDeploymentID1");

    function _setAllocator(address newAllocator) internal {
        vm.prank(governor);
        rm.setIssuanceAllocator(IIssuanceAllocationDistribution(newAllocator));
    }

    // -- setIssuanceAllocator: ERC-165 validation --

    function test_ERC165Validation_SetsAllocatorThatSupportsTheInterface() public {
        vm.expectEmit(address(rm));
        emit IssuanceAllocatorSet(
            IIssuanceAllocationDistribution(address(0)),
            IIssuanceAllocationDistribution(address(allocator))
        );
        _setAllocator(address(allocator));

        assertEq(address(rm.getIssuanceAllocator()), address(allocator));
    }

    function test_ERC165Validation_RevertWhen_AllocatorIsEOA() public {
        vm.prank(governor);
        vm.expectRevert();
        rm.setIssuanceAllocator(IIssuanceAllocationDistribution(indexer));
    }

    function test_ERC165Validation_RevertWhen_InterfaceNotSupported() public {
        MockERC165 mockERC165 = new MockERC165();

        vm.prank(governor);
        vm.expectRevert(bytes("Contract does not support IIssuanceAllocationDistribution interface"));
        rm.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockERC165)));
    }

    function test_ERC165Validation_RevertWhen_InterfaceNotSupportedBeforeRewardsUpdate() public {
        MockERC165 mockERC165 = new MockERC165();

        vm.prank(governor);
        vm.expectRevert(bytes("Contract does not support IIssuanceAllocationDistribution interface"));
        rm.setIssuanceAllocator(IIssuanceAllocationDistribution(address(mockERC165)));
    }

    // -- setIssuanceAllocator: access control --

    function test_AccessControl_RevertWhen_CalledByNonGovernor() public {
        vm.prank(indexer);
        vm.expectRevert(bytes("Only Controller governor"));
        rm.setIssuanceAllocator(IIssuanceAllocationDistribution(address(allocator)));
    }

    // -- setIssuanceAllocator: state management --

    function test_StateManagement_AllowsDisablingWithZeroAddress() public {
        _setAllocator(address(allocator));
        assertEq(address(rm.getIssuanceAllocator()), address(allocator));

        vm.expectEmit(address(rm));
        emit IssuanceAllocatorSet(
            IIssuanceAllocationDistribution(address(allocator)),
            IIssuanceAllocationDistribution(address(0))
        );
        _setAllocator(address(0));

        assertEq(address(rm.getIssuanceAllocator()), address(0));

        // Local issuancePerBlock is used again, both getters agree
        assertEq(rm.getAllocatedIssuancePerBlock(), ISSUANCE_PER_BLOCK);
        assertEq(rm.getRawIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    function test_StateManagement_EmitsIssuanceAllocatorSet() public {
        vm.expectEmit(address(rm));
        emit IssuanceAllocatorSet(
            IIssuanceAllocationDistribution(address(0)),
            IIssuanceAllocationDistribution(address(allocator))
        );
        _setAllocator(address(allocator));
    }

    function test_StateManagement_DoesNotEmitWhenSettingSameAllocator() public {
        _setAllocator(address(allocator));

        vm.recordLogs();
        _setAllocator(address(allocator));
        _assertNotEmitted(vm.getRecordedLogs(), IssuanceAllocatorSet.selector);
    }

    function test_StateManagement_UpdatesRewardsBeforeChangingAllocator() public {
        // Old test only checked the allocator was set; the pre-change update is also visible in the block marker
        vm.roll(block.number + 1);
        _setAllocator(address(allocator));

        assertEq(address(rm.getIssuanceAllocator()), address(allocator));
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);
    }

    // -- getAllocatedIssuancePerBlock --

    function test_GetAllocatedIssuancePerBlock_ReturnsIssuancePerBlockWhenNoAllocatorSet() public {
        uint256 expectedIssuance = 100.025 ether;
        vm.prank(governor);
        rm.setIssuancePerBlock(expectedIssuance);

        assertEq(address(rm.getIssuanceAllocator()), address(0));

        assertEq(rm.getAllocatedIssuancePerBlock(), expectedIssuance);
        assertEq(rm.getRawIssuancePerBlock(), expectedIssuance);
    }

    function test_GetAllocatedIssuancePerBlock_ReturnsValueFromAllocatorWhenSet() public {
        _setAllocator(address(allocator));
        assertEq(address(rm.getIssuanceAllocator()), address(allocator));

        // RewardsManager is a self-minting target with 25 GRT per block
        uint256 expectedIssuance = 25 ether;
        allocator.setTargetAllocation(address(rm), 0, expectedIssuance, true);

        // Allocated getter returns the allocator value, raw getter still returns storage value
        assertEq(rm.getAllocatedIssuancePerBlock(), expectedIssuance);
        assertEq(rm.getRawIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    function test_GetAllocatedIssuancePerBlock_ZeroWhenTargetNotRegisteredAsSelfMinter() public {
        _setAllocator(address(allocator));

        // RewardsManager is an allocator-minting target (only allocator issuance)
        allocator.setTargetAllocation(address(rm), 25 ether, 0, false);

        assertEq(rm.getAllocatedIssuancePerBlock(), 0);
        assertEq(rm.getRawIssuancePerBlock(), ISSUANCE_PER_BLOCK);
    }

    // -- setIssuancePerBlock --

    function test_SetIssuancePerBlock_AllowedWhenAllocatorIsSet() public {
        _setAllocator(address(allocator));

        uint256 newIssuancePerBlock = 100 ether;
        vm.prank(governor);
        rm.setIssuancePerBlock(newIssuancePerBlock);

        assertEq(rm.issuancePerBlock(), newIssuancePerBlock);
        assertEq(rm.getRawIssuancePerBlock(), newIssuancePerBlock);

        // The effective issuance still comes from the allocator (no target registered, so zero)
        assertNotEq(rm.getAllocatedIssuancePerBlock(), newIssuancePerBlock);
        assertEq(rm.getAllocatedIssuancePerBlock(), 0);
    }

    // -- beforeIssuanceAllocationChange --

    function test_BeforeIssuanceAllocationChange_HandlesCallsFromAnyoneAndTheAllocator() public {
        _setAllocator(address(allocator));

        // Anyone can call this function
        vm.roll(block.number + 1);
        vm.prank(governor);
        rm.beforeIssuanceAllocationChange();
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);

        // Also succeeds when called by the allocator
        vm.roll(block.number + 1);
        allocator.callBeforeIssuanceAllocationChange(address(rm));
        assertEq(rm.accRewardsPerSignalLastBlockUpdated(), block.number);
    }

    // -- issuance allocator integration --

    function test_IssuanceAllocatorIntegration_AccumulatesRewardsUsingAllocatorRateOverTime() public {
        uint256 totalSignal = 1000 ether;
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, totalSignal);

        // Allocator rate of 50 GRT per block, different from the local 200
        uint256 allocatorRate = 50 ether;
        allocator.setTargetAllocation(address(rm), 0, allocatorRate, false);
        _setAllocator(address(allocator));

        uint256 rewardsAfterSet = rm.getAccRewardsPerSignal();

        uint256 blocksToMine = 10;
        vm.roll(block.number + blocksToMine);

        uint256 actualAccrued = rm.getAccRewardsPerSignal() - rewardsAfterSet;

        // (rate x blocks) / totalSignal = 0.5 GRT per signal
        uint256 expectedAccrued = (allocatorRate * blocksToMine * 1e18) / totalSignal;
        assertEq(actualAccrued, expectedAccrued);

        // Not the local rate, which would be 4x higher
        assertNotEq(actualAccrued, _expectedRewardsPerSignal(blocksToMine, totalSignal));
    }

    function test_IssuanceAllocatorIntegration_MaintainsRewardConsistencyWhenSwitchingBetweenRates() public {
        uint256 totalSignal = 2000 ether;
        _signal(SUBGRAPH_DEPLOYMENT_ID_1, totalSignal);

        uint256 rewards0 = rm.getAccRewardsPerSignal();
        // Sum of every phase and transition accrual, checked against the overall difference at the end
        uint256 totalExpected;
        uint256 previous = rewards0;
        uint256 allocatorRate = 100 ether;

        // Phase 1: accrue at the local rate (200 GRT per block)
        vm.roll(block.number + 5);
        uint256 current = rm.getAccRewardsPerSignal();
        assertEq(current - previous, _expectedRewardsPerSignal(5, totalSignal));
        totalExpected += current - previous;
        previous = current;

        // Phase 2: switch to the allocator at 100 GRT per block. The switch happens one block later (the block
        // Hardhat mined for the tx), which still accrues at the local rate
        allocator.setTargetAllocation(address(rm), 0, allocatorRate, false);
        vm.roll(block.number + 1);
        _setAllocator(address(allocator));
        current = rm.getAccRewardsPerSignal();
        assertEq(current - previous, _expectedRewardsPerSignal(1, totalSignal));
        totalExpected += current - previous;
        previous = current;

        vm.roll(block.number + 8);
        current = rm.getAccRewardsPerSignal();
        assertEq(current - previous, (allocatorRate * 8 * 1e18) / totalSignal);
        totalExpected += current - previous;
        previous = current;

        // Phase 3: switch back to the local rate. The block of the switch still accrues at the allocator rate
        vm.roll(block.number + 1);
        _setAllocator(address(0));
        current = rm.getAccRewardsPerSignal();
        assertEq(current - previous, (allocatorRate * 1 * 1e18) / totalSignal);
        totalExpected += current - previous;
        previous = current;

        vm.roll(block.number + 4);
        current = rm.getAccRewardsPerSignal();
        assertEq(current - previous, _expectedRewardsPerSignal(4, totalSignal));
        totalExpected += current - previous;

        // All rewards from start to end equal the sum of the phases and the transition blocks
        assertEq(current - rewards0, totalExpected);
    }
}
