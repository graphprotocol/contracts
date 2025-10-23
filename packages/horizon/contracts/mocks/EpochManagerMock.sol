// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IEpochManager } from "@graphprotocol/interfaces/contracts/contracts/epochs/IEpochManager.sol";

/**
 * @title EpochManagerMock
 * @author Edge & Node
 * @notice Mock implementation of the EpochManager for testing
 */
contract EpochManagerMock is IEpochManager {
    // -- Variables --

    /// @notice Length of an epoch in blocks
    uint256 public epochLength;
    /// @notice Last epoch that was run
    uint256 public lastRunEpoch;
    /// @notice Last epoch when the length was updated
    uint256 public lastLengthUpdateEpoch;
    /// @notice Block number when the length was last updated
    uint256 public lastLengthUpdateBlock;

    // -- Configuration --

    /**
     * @notice Set the epoch length
     * @param epochLength_ New epoch length in blocks
     */
    function setEpochLength(uint256 epochLength_) public {
        lastLengthUpdateEpoch = 1;
        lastLengthUpdateBlock = blockNum();
        epochLength = epochLength_;
    }

    // -- Epochs

    /**
     * @notice Run the current epoch
     */
    function runEpoch() public {
        lastRunEpoch = currentEpoch();
    }

    // -- Getters --

    /**
     * @notice Check if the current epoch has been run
     * @return True if the current epoch has been run
     */
    function isCurrentEpochRun() public view returns (bool) {
        return lastRunEpoch == currentEpoch();
    }

    /**
     * @notice Get the current block number
     * @return The current block number
     */
    function blockNum() public view returns (uint256) {
        return block.number;
    }

    /**
     * @notice Get the hash of a specific block
     * @param block_ Block number to get hash for
     * @return The block hash
     */
    function blockHash(uint256 block_) public view returns (bytes32) {
        return blockhash(block_);
    }

    /**
     * @notice Get the current epoch number
     * @return The current epoch number
     */
    function currentEpoch() public view returns (uint256) {
        return lastLengthUpdateEpoch + epochsSinceUpdate();
    }

    /**
     * @notice Get the block number when the current epoch started
     * @return The block number when the current epoch started
     */
    function currentEpochBlock() public view returns (uint256) {
        return lastLengthUpdateBlock + (epochsSinceUpdate() * epochLength);
    }

    /**
     * @notice Get the number of blocks since the current epoch started
     * @return The number of blocks since the current epoch started
     */
    function currentEpochBlockSinceStart() public view returns (uint256) {
        return blockNum() - currentEpochBlock();
    }

    /**
     * @notice Get the number of epochs since a given epoch
     * @param epoch_ The epoch to compare against
     * @return The number of epochs since the given epoch
     */
    function epochsSince(uint256 epoch_) public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return epoch_ < epoch ? (epoch - epoch_) : 0;
    }

    /**
     * @notice Get the number of epochs since the last length update
     * @return The number of epochs since the last length update
     */
    function epochsSinceUpdate() public view returns (uint256) {
        return (blockNum() - lastLengthUpdateBlock) / epochLength;
    }
}
