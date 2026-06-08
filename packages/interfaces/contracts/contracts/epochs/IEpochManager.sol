// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Epoch Manager Interface
 * @author Edge & Node
 * @notice Interface for the Epoch Manager contract that handles protocol epochs
 */
interface IEpochManager {
    // -- Configuration --

    /**
     * @notice Set epoch length to `epochLength` blocks
     * @param epochLength Epoch length in blocks
     */
    function setEpochLength(uint256 epochLength) external;

    // -- Epochs

    /**
     * @dev Run a new epoch, should be called once at the start of any epoch.
     * @notice Perform state changes for the current epoch
     */
    function runEpoch() external;

    // -- Getters --

    /**
     * @notice Check if the current epoch has been run
     * @return True if current epoch has been run, false otherwise
     */
    function isCurrentEpochRun() external view returns (bool);

    /**
     * @notice Get the current block number
     * @return Current block number
     */
    function blockNum() external view returns (uint256);

    /**
     * @notice Get the hash of a specific block
     * @param block Block number to get hash for
     * @return Block hash
     */
    function blockHash(uint256 block) external view returns (bytes32);

    /**
     * @notice Get the current epoch number
     * @return Current epoch number
     */
    function currentEpoch() external view returns (uint256);

    /**
     * @notice Get the block number when the current epoch started
     * @return Block number of current epoch start
     */
    function currentEpochBlock() external view returns (uint256);

    /**
     * @notice Get the number of blocks since the current epoch started
     * @return Number of blocks since current epoch start
     */
    function currentEpochBlockSinceStart() external view returns (uint256);

    /**
     * @notice Get the number of epochs since a given epoch
     * @param epoch Epoch to calculate from
     * @return Number of epochs since the given epoch
     */
    function epochsSince(uint256 epoch) external view returns (uint256);

    /**
     * @notice Get the number of epochs since the last epoch length update
     * @return Number of epochs since last update
     */
    function epochsSinceUpdate() external view returns (uint256);
}
