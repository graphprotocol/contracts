// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";

contract EpochManagerMock is IEpochManager {
    // -- Variables --

    uint256 public epochLength;
    uint256 public lastRunEpoch;
    uint256 public lastLengthUpdateEpoch;
    uint256 public lastLengthUpdateBlock;

    // -- Configuration --

    function setEpochLength(uint256 epochLength_) public {
        lastLengthUpdateEpoch = 1;
        lastLengthUpdateBlock = blockNum();
        epochLength = epochLength_;
    }

    // -- Epochs

    function runEpoch() public {
        lastRunEpoch = currentEpoch();
    }

    // -- Getters --

    function isCurrentEpochRun() public view returns (bool) {
        return lastRunEpoch == currentEpoch();
    }

    function blockNum() public view returns (uint256) {
        return block.number;
    }

    function blockHash(uint256 block_) public view returns (bytes32) {
        return blockhash(block_);
    }

    function currentEpoch() public view returns (uint256) {
        return lastLengthUpdateEpoch + epochsSinceUpdate();
    }

    function currentEpochBlock() public view returns (uint256) {
        return lastLengthUpdateBlock + (epochsSinceUpdate() * epochLength);
    }

    function currentEpochBlockSinceStart() public view returns (uint256) {
        return blockNum() - currentEpochBlock();
    }

    function epochsSince(uint256 epoch_) public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return epoch_ < epoch ? (epoch - epoch_) : 0;
    }

    function epochsSinceUpdate() public view returns (uint256) {
        return (blockNum() - lastLengthUpdateBlock) / epochLength;
    }
}
