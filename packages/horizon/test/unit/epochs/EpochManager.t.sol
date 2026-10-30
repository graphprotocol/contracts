// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IEpochManagerLike } from "./IEpochManagerLike.sol";
import { ProtocolFixture } from "../shared/ProtocolFixture.t.sol";

contract EpochManagerTest is ProtocolFixture {
    event EpochRun(uint256 indexed epoch, address caller);
    event EpochLengthUpdate(uint256 indexed epoch, uint256 epochLength);

    uint256 internal constant DEFAULT_EPOCH_LENGTH = 60;
    uint256 internal constant EPOCH_LENGTH = 3;

    IEpochManagerLike internal epochManager;
    address internal me = makeAddr("me");

    function setUp() public {
        vm.warp(1_700_000_000);
        _deployProtocolBase();
        address impl = _deployArtifact(string.concat(PKG_ARTIFACTS, "epochs/EpochManager.sol/EpochManager.json"), "");
        epochManager = IEpochManagerLike(
            _deployBehindProxy(
                impl,
                abi.encodeCall(IEpochManagerLike.initialize, (address(controller), DEFAULT_EPOCH_LENGTH))
            )
        );
    }

    modifier withLifecycleLength() {
        vm.prank(governor);
        epochManager.setEpochLength(EPOCH_LENGTH);
        _;
    }

    function _rollToNextEpoch() internal {
        vm.roll(epochManager.currentEpochBlock() + EPOCH_LENGTH);
    }

    // -- configuration --

    function test_Configuration_SetEpochLength() public {
        assertEq(epochManager.epochLength(), DEFAULT_EPOCH_LENGTH);

        uint256 newEpochLength = 4;
        uint256 currentEpoch = epochManager.currentEpoch();
        vm.expectEmit(address(epochManager));
        emit EpochLengthUpdate(currentEpoch, newEpochLength);
        vm.prank(governor);
        epochManager.setEpochLength(newEpochLength);
        assertEq(epochManager.epochLength(), newEpochLength);
    }

    function test_Configuration_RevertWhen_EpochLengthZero() public {
        vm.expectRevert(bytes("Epoch length cannot be 0"));
        vm.prank(governor);
        epochManager.setEpochLength(0);
    }

    function test_Configuration_RevertWhen_EpochLengthSame() public {
        vm.expectRevert(bytes("Epoch length must be different to current"));
        vm.prank(governor);
        epochManager.setEpochLength(DEFAULT_EPOCH_LENGTH);
    }

    // -- epoch lifecycle: calculations --

    function test_Calculations_FirstEpochIsOne() public withLifecycleLength {
        assertEq(epochManager.currentEpoch(), 1);
    }

    function test_Calculations_BlockNum() public withLifecycleLength {
        assertEq(epochManager.blockNum(), block.number);
        vm.roll(block.number + 7);
        assertEq(epochManager.blockNum(), block.number);
    }

    function test_Calculations_SameStartingBlockOnSameEpoch() public withLifecycleLength {
        // Move right to the start of a new epoch
        uint256 blocksToNextEpoch = EPOCH_LENGTH - epochManager.currentEpochBlockSinceStart();
        vm.roll(epochManager.blockNum() + blocksToNextEpoch);

        uint256 beforeCurrentEpochBlock = epochManager.currentEpochBlock();

        // Advance block - will not jump to next epoch
        vm.roll(block.number + 1);

        assertEq(epochManager.currentEpochBlock(), beforeCurrentEpochBlock);
    }

    function test_Calculations_NextStartingBlockOnNextEpoch() public withLifecycleLength {
        uint256 beforeCurrentEpochBlock = epochManager.currentEpochBlock();

        vm.roll(beforeCurrentEpochBlock + EPOCH_LENGTH);

        assertEq(epochManager.currentEpochBlock(), beforeCurrentEpochBlock + EPOCH_LENGTH);
    }

    function test_Calculations_NextEpochWhenAdvancePastLength() public withLifecycleLength {
        uint256 nextEpoch = epochManager.currentEpoch() + 1;

        _rollToNextEpoch();

        assertEq(epochManager.currentEpoch(), nextEpoch);
    }

    function test_EpochManager_SameBlockDoesNotAdvance() public withLifecycleLength {
        uint256 epochBefore = epochManager.currentEpoch();
        uint256 epochBlockBefore = epochManager.currentEpochBlock();

        assertEq(epochManager.currentEpoch(), epochBefore);
        assertEq(epochManager.currentEpochBlock(), epochBlockBefore);

        vm.roll(epochBlockBefore + EPOCH_LENGTH - 1);
        assertEq(epochManager.currentEpoch(), epochBefore);
        assertEq(epochManager.currentEpochBlock(), epochBlockBefore);

        vm.roll(epochBlockBefore + EPOCH_LENGTH);
        assertEq(epochManager.currentEpoch(), epochBefore + 1);
        assertEq(epochManager.currentEpochBlock(), epochBlockBefore + EPOCH_LENGTH);
    }

    function test_Calculations_EpochsSince() public withLifecycleLength {
        uint256 startEpoch = epochManager.currentEpoch();
        uint256 startBlock = epochManager.currentEpochBlock();

        vm.roll(startBlock + 2 * EPOCH_LENGTH + 1);

        assertEq(epochManager.currentEpoch(), startEpoch + 2);
        assertEq(epochManager.epochsSince(startEpoch), 2);
        assertEq(epochManager.epochsSince(startEpoch + 1), 1);
        assertEq(epochManager.epochsSince(startEpoch + 2), 0);
        assertEq(epochManager.epochsSince(startEpoch + 3), 0);
        assertEq(epochManager.epochsSinceUpdate(), 2);
        assertEq(epochManager.currentEpochBlockSinceStart(), 1);
    }

    function test_Calculations_RevertWhen_BlockHashNotPast() public withLifecycleLength {
        vm.roll(1000);
        uint256 current = epochManager.blockNum();

        vm.expectRevert(bytes("Can only retrieve past block hashes"));
        epochManager.blockHash(current);

        vm.expectRevert(bytes("Can only retrieve past block hashes"));
        epochManager.blockHash(current + 1);
    }

    function test_Calculations_RevertWhen_BlockHashTooOld() public withLifecycleLength {
        vm.roll(1000);

        vm.expectRevert(bytes("Can only retrieve hashes for last 256 blocks"));
        epochManager.blockHash(1000 - 257);
    }

    // -- epoch lifecycle: progression --

    function test_Progression_NotRun() public withLifecycleLength {
        _rollToNextEpoch();
        assertFalse(epochManager.isCurrentEpochRun());
    }

    function test_Progression_RunEpoch() public withLifecycleLength {
        _rollToNextEpoch();

        uint256 currentEpoch = epochManager.currentEpoch();
        vm.expectEmit(address(epochManager));
        emit EpochRun(currentEpoch, me);
        vm.prank(me);
        epochManager.runEpoch();

        assertEq(epochManager.lastRunEpoch(), currentEpoch);
    }

    function test_Progression_AlreadyRun() public withLifecycleLength {
        _rollToNextEpoch();
        epochManager.runEpoch();

        assertTrue(epochManager.isCurrentEpochRun());
    }

    function test_Progression_RevertWhen_AlreadyRun() public withLifecycleLength {
        _rollToNextEpoch();
        epochManager.runEpoch();

        vm.expectRevert(bytes("Current epoch already run"));
        epochManager.runEpoch();
    }
}
