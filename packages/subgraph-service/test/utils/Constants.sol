// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract Constants {
    // Dispute Manager
    uint64 internal constant disputePeriod = 300; // 5 minutes
    uint256 internal constant minimumDeposit = 100 ether; // 100 GRT
    uint32 internal constant fishermanRewardPercentage = 100000; // 10%
    uint32 internal constant maxSlashingPercentage = 500000; // 50%
    // Subgraph Service
    uint256 internal constant minimumProvisionTokens = 1000 ether;
    uint32 internal constant delegationRatio = 16;
}