// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

// solhint-disable use-natspec

import { IEpochManager } from "../contracts/epochs/IEpochManager.sol";

interface IEpochManagerToolshed is IEpochManager {
    function epochLength() external view returns (uint256);
}
