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
}