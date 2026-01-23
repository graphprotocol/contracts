// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

abstract contract Constants {
    uint256 internal constant MAX_TOKENS = 10_000_000_000 ether;
    uint256 internal constant MAX_PPM = 1_000_000;
    uint256 internal constant EPOCH_LENGTH = 1;
    // Dispute Manager
    uint64 internal constant DISPUTE_PERIOD = 7 days;
    uint256 internal constant MIN_DISPUTE_DEPOSIT = 1 ether; // 1 GRT
    uint256 internal constant DISPUTE_DEPOSIT = 100 ether; // 100 GRT
    uint32 internal constant FISHERMAN_REWARD_PERCENTAGE = 500000; // 50%
    uint32 internal constant MAX_SLASHING_PERCENTAGE = 100000; // 10%
    // Subgraph Service
    uint256 internal constant MINIMUM_PROVISION_TOKENS = 1000 ether;
    uint256 internal constant MAXIMUM_PROVISION_TOKENS = type(uint256).max;
    uint32 internal constant DELEGATION_RATIO = 16;
    uint256 public constant STAKE_TO_FEES_RATIO = 2;
    uint256 public constant MAX_POI_STALENESS = 28 days;
    uint256 public constant CURATION_CUT = 10000;
    // Staking
    uint64 internal constant MAX_WAIT_PERIOD = 28 days;
    uint256 internal constant MIN_DELEGATION = 1 ether;
    // GraphEscrow parameters
    uint256 internal constant WITHDRAW_ESCROW_THAWING_PERIOD = 60;
    // GraphPayments parameters
    uint256 internal constant PROTOCOL_PAYMENT_CUT = 10000;
    // RewardsMananger parameters
    uint256 public constant REWARDS_PER_SIGNAL = 10000;
    uint256 public constant REWARDS_PER_SUBGRAPH_ALLOCATION_UPDATE = 1000;
    // GraphTallyCollector parameters
    uint256 public constant REVOKE_SIGNER_THAWING_PERIOD = 7 days;
}
