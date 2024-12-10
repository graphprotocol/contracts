// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

abstract contract Constants {
    uint256 internal constant MAX_TOKENS = 10_000_000_000 ether;
    uint256 internal constant MAX_PPM = 1_000_000;
    uint256 internal constant EPOCH_LENGTH = 1;
    // Dispute Manager
    uint64 internal constant disputePeriod = 7 days;
    uint256 internal constant disputeDeposit = 100 ether; // 100 GRT
    uint32 internal constant fishermanRewardPercentage = 500000; // 50%
    uint32 internal constant maxSlashingPercentage = 500000; // 50%
    // Subgraph Service
    uint256 internal constant minimumProvisionTokens = 1000 ether;
    uint256 internal constant maximumProvisionTokens = type(uint256).max;
    uint32 internal constant delegationRatio = 16;
    uint256 public constant stakeToFeesRatio = 2;
    uint256 public constant maxPOIStaleness = 28 days;
    uint256 public constant curationCut = 10000;
    // Staking
    uint64 internal constant MAX_WAIT_PERIOD = 28 days;
    // GraphEscrow parameters
    uint256 internal constant withdrawEscrowThawingPeriod = 60;
    // GraphPayments parameters
    uint256 internal constant protocolPaymentCut = 10000;
    // RewardsMananger parameters
    uint256 public constant rewardsPerSignal = 10000;
    uint256 public constant rewardsPerSubgraphAllocationUpdate = 1000;
    // TAPCollector parameters
    uint256 public constant revokeSignerThawingPeriod = 7 days;
}
