// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;

interface ILegacyRewardsManager {
    function getRewards(address allocationID) external view returns (uint256);
}
