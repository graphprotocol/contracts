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
    uint32 public constant stakeToFeesRatio = 2;
    uint256 public constant maxPOIStaleness = 28 days;
    uint128 public constant serviceCut = 10000; 
    uint128 public constant curationCut = 10000;
    // Staking
    uint64 internal constant MAX_THAWING_PERIOD = 28 days;
    // GraphEscrow parameters
    uint256 internal constant withdrawEscrowThawingPeriod = 60;
    uint256 internal constant revokeCollectorThawingPeriod = 60;
    // GraphPayments parameters
    uint256 internal constant protocolPaymentCut = 10000;
    // RewardsMananger parameters
    uint256 public constant rewardsPerSignal = 10000;
}