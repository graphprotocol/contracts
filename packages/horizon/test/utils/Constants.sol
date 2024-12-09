// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

abstract contract Constants {
    uint32 internal constant MAX_PPM = 1000000; // 100% in parts per million
    uint256 internal constant delegationFeeCut = 100000; // 10% in parts per million
    uint256 internal constant MAX_STAKING_TOKENS = 10_000_000_000 ether;
    // GraphEscrow parameters
    uint256 internal constant withdrawEscrowThawingPeriod = 60;
    uint256 internal constant revokeCollectorThawingPeriod = 60;
    // GraphPayments parameters
    uint256 internal constant protocolPaymentCut = 10000;
    // Staking constants
    uint256 internal constant MAX_THAW_REQUESTS = 100;
    uint64 internal constant MAX_THAWING_PERIOD = 28 days;
    uint32 internal constant THAWING_PERIOD_IN_BLOCKS = 300;
    uint256 internal constant MIN_DELEGATION = 1e18;
    // Epoch manager
    uint256 internal constant EPOCH_LENGTH = 1;
    // Rewards manager
    uint256 internal constant ALLOCATIONS_REWARD_CUT = 100 ether;
    // TAPCollector
    uint256 internal constant revokeSignerThawingPeriod = 7 days;
}