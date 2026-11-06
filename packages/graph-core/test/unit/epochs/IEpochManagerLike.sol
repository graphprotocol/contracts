// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IEpochManager } from "@graphprotocol/interfaces/contracts/contracts/epochs/IEpochManager.sol";

/// IEpochManager plus the initializer, storage getters and events the interface omits.
interface IEpochManagerLike is IEpochManager {
    event EpochRun(uint256 indexed epoch, address caller);
    event EpochLengthUpdate(uint256 indexed epoch, uint256 epochLength);

    function initialize(address controller, uint256 epochLength) external;

    function epochLength() external view returns (uint256);

    function lastRunEpoch() external view returns (uint256);

    function lastLengthUpdateEpoch() external view returns (uint256);

    function lastLengthUpdateBlock() external view returns (uint256);
}
