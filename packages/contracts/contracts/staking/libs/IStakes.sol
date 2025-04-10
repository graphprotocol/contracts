// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || 0.8.27;
pragma abicoder v2;

interface IStakes {
    struct Indexer {
        uint256 tokensStaked; // Tokens on the indexer stake (staked by the indexer)
        uint256 tokensAllocated; // Tokens used in allocations
        uint256 tokensLocked; // Tokens locked for withdrawal subject to thawing period
        uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
    }
}
