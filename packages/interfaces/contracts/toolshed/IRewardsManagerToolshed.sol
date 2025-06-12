// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6 || 0.8.27;

import { IRewardsManager } from "../contracts/rewards/IRewardsManager.sol";

interface IRewardsManagerToolshed is IRewardsManager {
    function subgraphService() external view returns (address);
}
