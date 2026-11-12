// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";

import { RewardsManagerSharedTest } from "./shared.t.sol";

/// Snapshot inversion on upgrade. With A = accRewardsForSubgraph, S = accRewardsForSubgraphSnapshot and
/// P = rewards since the signal snapshot, pre-upgrade storage can hold A < S. The update computes
/// (A + P) - S, adding P before subtracting S, so it never underflows and the gap S - A is not paid twice.
/// The inverted state is written with `vm.store`.
contract RewardsManagerSnapshotInversionTest is RewardsManagerSharedTest {
    bytes32 internal constant SUBGRAPH_DEPLOYMENT_ID = keccak256("subgraphDeploymentID");

    /// `subgraphs` in RewardsManagerV1Storage: Managed's controller (0), _addressCache (1) and __gap[10] (2-11),
    /// then __DEPRECATED_issuanceRate (12), accRewardsPerSignal (13), accRewardsPerSignalLastBlockUpdated (14),
    /// subgraphAvailabilityOracle (15)
    uint256 internal constant SUBGRAPHS_MAPPING_SLOT = 16;
    uint256 internal constant ACC_REWARDS_PER_SIGNAL_SLOT = 13;
    uint256 internal constant ACC_REWARDS_PER_SIGNAL_LAST_BLOCK_UPDATED_SLOT = 14;

    /// Fields of `IRewardsManager.Subgraph`, as offsets from the struct's base slot
    uint256 internal constant ACC_REWARDS_FOR_SUBGRAPH = 0;
    uint256 internal constant ACC_REWARDS_FOR_SUBGRAPH_SNAPSHOT = 1;
    uint256 internal constant ACC_REWARDS_PER_SIGNAL_SNAPSHOT = 2;
    uint256 internal constant ACC_REWARDS_PER_ALLOCATED_TOKEN = 3;

    /// Blocks mined by the old setup between the allocation and its signal update
    uint256 internal constant SETUP_BLOCKS = 50;

    address internal allocationID = makeAddr("allocationID");

    // -- Helpers --

    function _subgraphStorageSlot(bytes32 sd, uint256 fieldOffset) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(sd, SUBGRAPHS_MAPPING_SLOT))) + fieldOffset);
    }

    /// Signal, allocate, accrue `SETUP_BLOCKS`, then sync the subgraph with a signal update, so A > 0.
    function _setupSubgraphWithAllocation() internal {
        _signalThenAllocate(SUBGRAPH_DEPLOYMENT_ID, allocationID);
        vm.roll(block.number + SETUP_BLOCKS);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
    }

    /// The state left by the old `onSubgraphAllocationUpdate`, which wrote S from a view (storage + pending)
    /// while A stayed at its stored value: S = A + gap.
    function _createInvertedState(uint256 gap) internal {
        uint256 invertedSnapshot = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsForSubgraph + gap;
        vm.store(
            address(rm),
            _subgraphStorageSlot(SUBGRAPH_DEPLOYMENT_ID, ACC_REWARDS_FOR_SUBGRAPH_SNAPSHOT),
            bytes32(invertedSnapshot)
        );

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(sg.accRewardsForSubgraphSnapshot, invertedSnapshot);
        assertLt(sg.accRewardsForSubgraph, sg.accRewardsForSubgraphSnapshot);
    }

    function _perAllocatedToken(uint256 rewards) internal pure returns (uint256) {
        return _expectedRewardsPerAllocatedToken(rewards, ALLOCATION);
    }

    // -- storage slot verification --

    function test_SnapshotInversion_StorageSlotsMatchLayout() public {
        _setupSubgraphWithAllocation();

        IRewardsManager.Subgraph memory before = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertTrue(before.accRewardsForSubgraph != 0);
        assertTrue(before.accRewardsForSubgraphSnapshot != 0);
        assertTrue(before.accRewardsPerSignalSnapshot != 0);
        assertTrue(before.accRewardsPerAllocatedToken != 0);

        // The inherited prefix: the plain slots before the mapping
        assertEq(uint256(vm.load(address(rm), bytes32(ACC_REWARDS_PER_SIGNAL_SLOT))), rm.accRewardsPerSignal());
        assertEq(
            uint256(vm.load(address(rm), bytes32(ACC_REWARDS_PER_SIGNAL_LAST_BLOCK_UPDATED_SLOT))),
            rm.accRewardsPerSignalLastBlockUpdated()
        );

        // Each struct field reads back through the getter
        bytes32 sd = SUBGRAPH_DEPLOYMENT_ID;
        assertEq(
            uint256(vm.load(address(rm), _subgraphStorageSlot(sd, ACC_REWARDS_FOR_SUBGRAPH))),
            before.accRewardsForSubgraph
        );
        assertEq(
            uint256(vm.load(address(rm), _subgraphStorageSlot(sd, ACC_REWARDS_FOR_SUBGRAPH_SNAPSHOT))),
            before.accRewardsForSubgraphSnapshot
        );
        assertEq(
            uint256(vm.load(address(rm), _subgraphStorageSlot(sd, ACC_REWARDS_PER_SIGNAL_SNAPSHOT))),
            before.accRewardsPerSignalSnapshot
        );
        assertEq(
            uint256(vm.load(address(rm), _subgraphStorageSlot(sd, ACC_REWARDS_PER_ALLOCATED_TOKEN))),
            before.accRewardsPerAllocatedToken
        );

        // A write to the snapshot field changes only that field
        uint256 testValue = 12345678901234567890;
        vm.store(address(rm), _subgraphStorageSlot(sd, ACC_REWARDS_FOR_SUBGRAPH_SNAPSHOT), bytes32(testValue));

        IRewardsManager.Subgraph memory sg = _subgraph(sd);
        assertEq(sg.accRewardsForSubgraphSnapshot, testValue);
        assertEq(sg.accRewardsForSubgraph, before.accRewardsForSubgraph);
        assertEq(sg.accRewardsPerSignalSnapshot, before.accRewardsPerSignalSnapshot);
        assertEq(sg.accRewardsPerAllocatedToken, before.accRewardsPerAllocatedToken);
    }

    // -- inverted state: accumulated < snapshot --

    function test_InvertedStateAccumulatedBelowSnapshot_SignalUpdateDoesNotRevert() public {
        _setupSubgraphWithAllocation();
        _createInvertedState(7000 ether);

        // P (50 blocks at 200 GRT) exceeds the gap
        vm.roll(block.number + 50);

        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
    }

    function test_InvertedStateAccumulatedBelowSnapshot_AllocationUpdateDoesNotRevert() public {
        _setupSubgraphWithAllocation();
        _createInvertedState(7000 ether);

        vm.roll(block.number + 50);

        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
    }

    function test_InvertedStateAccumulatedBelowSnapshot_SyncsSnapshotsAfterFirstCall() public {
        _setupSubgraphWithAllocation();
        _createInvertedState(7000 ether);

        vm.roll(block.number + 50);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);

        vm.roll(block.number + 10);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
    }

    // -- accounting correctness with inverted state --

    function test_AccountingCorrectnessWithInvertedState_ComputesUndistributedAsAPlusPMinusS() public {
        _setupSubgraphWithAllocation();
        IRewardsManager.Subgraph memory before = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        uint256 gap = 500 ether;
        _createInvertedState(gap);

        // P = 10 blocks, about 2000 GRT, more than the gap
        vm.roll(block.number + 10);
        uint256 pending = _subgraphRewards(10);
        assertGt(pending, gap);

        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        assertLt(before.accRewardsPerAllocatedToken, sg.accRewardsPerAllocatedToken);
        // (A + P) - S = (A + P) - (A + gap) = P - gap
        assertEq(
            sg.accRewardsPerAllocatedToken,
            before.accRewardsPerAllocatedToken + _perAllocatedToken(pending - gap)
        );
        assertEq(sg.accRewardsForSubgraph, before.accRewardsForSubgraph + pending);
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
    }

    function test_AccountingCorrectnessWithInvertedState_DoesNotDoubleCountGap() public {
        _setupSubgraphWithAllocation();
        IRewardsManager.Subgraph memory stateBefore = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        uint256 gap = 500 ether;
        _createInvertedState(gap);

        vm.roll(block.number + 20);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        uint256 perAllocAfterInverted = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken;

        vm.roll(block.number + 20);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        uint256 perAllocAfterNormal = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken;

        uint256 firstDelta = perAllocAfterInverted - stateBefore.accRewardsPerAllocatedToken;
        uint256 secondDelta = perAllocAfterNormal - perAllocAfterInverted;

        assertLt(firstDelta, secondDelta);
        assertEq(firstDelta, _perAllocatedToken(_subgraphRewards(20) - gap));
        assertEq(secondDelta, _perAllocatedToken(_subgraphRewards(20)));
    }

    function test_AccountingCorrectnessWithInvertedState_DistributesExactlyPendingMinusGap() public {
        _setupSubgraphWithAllocation();

        // Sync in the next block, as the next Hardhat transaction
        vm.roll(block.number + 1);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        uint256 perAllocBaseline = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken;

        uint256 gap = 500 ether;
        _createInvertedState(gap);

        vm.roll(block.number + 20);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        uint256 perAllocAfterInverted = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken;
        uint256 invertedDelta = perAllocAfterInverted - perAllocBaseline;

        vm.roll(block.number + 20);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        uint256 normalDelta = _subgraph(SUBGRAPH_DEPLOYMENT_ID).accRewardsPerAllocatedToken - perAllocAfterInverted;

        assertLt(invertedDelta, normalDelta);
        assertTrue(invertedDelta != 0);
        assertEq(invertedDelta, _perAllocatedToken(_subgraphRewards(20) - gap));
        assertEq(normalDelta, _perAllocatedToken(_subgraphRewards(20)));
    }

    // -- normal operation (no inversion) --

    function test_NormalOperationNoInversion_SyncedSnapshotSteadyState() public {
        _setupSubgraphWithAllocation();

        // Sync in the next block, as the next Hardhat transaction
        vm.roll(block.number + 1);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory synced = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(synced.accRewardsForSubgraphSnapshot, synced.accRewardsForSubgraph);

        vm.roll(block.number + 20);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        assertLt(synced.accRewardsPerAllocatedToken, sg.accRewardsPerAllocatedToken);
        assertEq(
            sg.accRewardsPerAllocatedToken,
            synced.accRewardsPerAllocatedToken + _perAllocatedToken(_subgraphRewards(20))
        );
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
    }

    function test_NormalOperationNoInversion_ZeroRewardsInSameBlock() public {
        _setupSubgraphWithAllocation();

        // Sync in the next block, as the next Hardhat transaction
        vm.roll(block.number + 1);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);
        IRewardsManager.Subgraph memory synced = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        // Same block: no vm.roll, so no new rewards
        uint256 accRewardsPerAllocatedToken = rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory sg = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(sg.accRewardsForSubgraphSnapshot, sg.accRewardsForSubgraph);
        assertEq(accRewardsPerAllocatedToken, synced.accRewardsPerAllocatedToken);
        assertEq(sg.accRewardsPerAllocatedToken, synced.accRewardsPerAllocatedToken);
        assertEq(sg.accRewardsForSubgraph, synced.accRewardsForSubgraph);
    }

    // -- realistic pre-upgrade scenario --

    function test_RealisticPreUpgradeScenario_HandlesArbitrumSepoliaStatePattern() public {
        _setupSubgraphWithAllocation();
        IRewardsManager.Subgraph memory state = _subgraph(SUBGRAPH_DEPLOYMENT_ID);

        // S = A + 7235 GRT, the gap observed on Arbitrum Sepolia
        uint256 observedGap = 7235 ether;
        vm.store(
            address(rm),
            _subgraphStorageSlot(SUBGRAPH_DEPLOYMENT_ID, ACC_REWARDS_FOR_SUBGRAPH_SNAPSHOT),
            bytes32(state.accRewardsForSubgraph + observedGap)
        );

        IRewardsManager.Subgraph memory inverted = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertLt(inverted.accRewardsForSubgraph, inverted.accRewardsForSubgraphSnapshot);

        vm.roll(block.number + 50);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);

        IRewardsManager.Subgraph memory healed = _subgraph(SUBGRAPH_DEPLOYMENT_ID);
        assertEq(healed.accRewardsForSubgraphSnapshot, healed.accRewardsForSubgraph);
        assertEq(healed.accRewardsForSubgraph, state.accRewardsForSubgraph + _subgraphRewards(50));
        assertEq(
            healed.accRewardsPerAllocatedToken,
            state.accRewardsPerAllocatedToken + _perAllocatedToken(_subgraphRewards(50) - observedGap)
        );

        vm.roll(block.number + 10);
        rm.onSubgraphAllocationUpdate(SUBGRAPH_DEPLOYMENT_ID);

        vm.roll(block.number + 10);
        rm.onSubgraphSignalUpdate(SUBGRAPH_DEPLOYMENT_ID);
    }
}
