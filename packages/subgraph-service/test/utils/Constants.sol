// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract Constants {
    uint256 internal constant MAX_TOKENS = 10_000_000_000 ether;
    // Dispute Manager
    uint64 internal constant disputePeriod = 300; // 5 minutes
    uint256 internal constant minimumDeposit = 100 ether; // 100 GRT
    uint32 internal constant fishermanRewardPercentage = 100000; // 10%
    uint32 internal constant maxSlashingPercentage = 500000; // 50%
    // Subgraph Service
    uint256 internal constant minimumProvisionTokens = 1000 ether;
    uint256 internal constant maximumProvisionTokens = type(uint256).max;
    uint32 internal constant delegationRatio = 16;
    // Staking
    uint64 internal constant MAX_THAWING_PERIOD = 28 days;
}