// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Constants {
    // GraphEscrow parameters
    uint256 internal constant withdrawEscrowThawingPeriod = 60;
    // GraphPayments parameters
    uint256 internal constant revokeCollectorThawingPeriod = 60;
    uint256 internal constant protocolPaymentCut = 10000;
}