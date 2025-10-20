// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-indexed-events, gas-small-strings, gas-strict-inequalities

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { Managed } from "../governance/Managed.sol";

import { EpochManagerV1Storage } from "./EpochManagerStorage.sol";
import { IEpochManager } from "@graphprotocol/interfaces/contracts/contracts/epochs/IEpochManager.sol";

/**
 * @title EpochManager contract
 * @author Edge & Node
 * @notice Produce epochs based on a number of blocks to coordinate contracts in the protocol.
 */
contract EpochManager is EpochManagerV1Storage, GraphUpgradeable, IEpochManager {
    using SafeMath for uint256;

    // -- Events --

    /**
     * @notice Emitted when an epoch is run
     * @param epoch The epoch number that was run
     * @param caller Address that called runEpoch()
     */
    event EpochRun(uint256 indexed epoch, address caller);

    /**
     * @notice Emitted when the epoch length is updated
     * @param epoch The epoch when the length was updated
     * @param epochLength The new epoch length in blocks
     */
    event EpochLengthUpdate(uint256 indexed epoch, uint256 epochLength);

    /**
     * @notice Initialize this contract.
     * @param _controller Address of the Controller contract
     * @param _epochLength Length of each epoch in blocks
     */
    function initialize(address _controller, uint256 _epochLength) external onlyImpl {
        require(_epochLength > 0, "Epoch length cannot be 0");

        Managed._initialize(_controller);

        // NOTE: We make the first epoch to be one instead of zero to avoid any issue
        // with composing contracts that may use zero as an empty value
        lastLengthUpdateEpoch = 1;
        lastLengthUpdateBlock = blockNum();
        epochLength = _epochLength;

        emit EpochLengthUpdate(lastLengthUpdateEpoch, epochLength);
    }

    /**
     * @inheritdoc IEpochManager
     */
    function setEpochLength(uint256 _epochLength) external override onlyGovernor {
        require(_epochLength > 0, "Epoch length cannot be 0");
        require(_epochLength != epochLength, "Epoch length must be different to current");

        lastLengthUpdateEpoch = currentEpoch();
        lastLengthUpdateBlock = currentEpochBlock();
        epochLength = _epochLength;

        emit EpochLengthUpdate(lastLengthUpdateEpoch, epochLength);
    }

    /**
     * @inheritdoc IEpochManager
     */
    function runEpoch() external override {
        // Check if already called for the current epoch
        require(!isCurrentEpochRun(), "Current epoch already run");

        lastRunEpoch = currentEpoch();

        // Hook for protocol general state updates

        emit EpochRun(lastRunEpoch, msg.sender);
    }

    /**
     * @inheritdoc IEpochManager
     */
    function isCurrentEpochRun() public view override returns (bool) {
        return lastRunEpoch == currentEpoch();
    }

    /**
     * @inheritdoc IEpochManager
     */
    function blockNum() public view override returns (uint256) {
        return block.number;
    }

    /**
     * @inheritdoc IEpochManager
     */
    function blockHash(uint256 _block) external view override returns (bytes32) {
        uint256 currentBlock = blockNum();

        require(_block < currentBlock, "Can only retrieve past block hashes");
        require(currentBlock < 256 || _block >= currentBlock - 256, "Can only retrieve hashes for last 256 blocks");

        return blockhash(_block);
    }

    /**
     * @inheritdoc IEpochManager
     */
    function currentEpoch() public view override returns (uint256) {
        return lastLengthUpdateEpoch.add(epochsSinceUpdate());
    }

    /**
     * @inheritdoc IEpochManager
     */
    function currentEpochBlock() public view override returns (uint256) {
        return lastLengthUpdateBlock.add(epochsSinceUpdate().mul(epochLength));
    }

    /**
     * @inheritdoc IEpochManager
     */
    function currentEpochBlockSinceStart() external view override returns (uint256) {
        return blockNum() - currentEpochBlock();
    }

    /**
     * @inheritdoc IEpochManager
     */
    function epochsSince(uint256 _epoch) external view override returns (uint256) {
        uint256 epoch = currentEpoch();
        return _epoch < epoch ? epoch.sub(_epoch) : 0;
    }

    /**
     * @inheritdoc IEpochManager
     */
    function epochsSinceUpdate() public view override returns (uint256) {
        return blockNum().sub(lastLengthUpdateBlock).div(epochLength);
    }
}
