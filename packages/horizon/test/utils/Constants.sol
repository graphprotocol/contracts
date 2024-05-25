// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Constants {
    uint256 internal constant MAX_PPM = 1000000; // 100% in parts per million
    uint256 internal constant delegationFeeCut = 100000; // 10% in parts per million
    // GraphEscrow parameters
    uint256 internal constant withdrawEscrowThawingPeriod = 60;
    uint256 internal constant revokeCollectorThawingPeriod = 60;
    // GraphPayments parameters
    uint256 internal constant protocolPaymentCut = 10000;
    // Staking constants
    uint256 internal constant MAX_THAW_REQUESTS = 100;
    uint256 internal constant MIN_PROVISION_SIZE = 1e18;
    uint32 internal constant MAX_MAX_VERIFIER_CUT = 1000000; // 100% in parts per million
    uint64 internal constant MAX_THAWING_PERIOD = 28 days;
    uint256 internal constant MIN_DELEGATION = 1e18;
}