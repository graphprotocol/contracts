// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

// TODO: create custom var-name-mixedcase

interface IHorizonStakingTypes {
    struct Provision {
        // service provider tokens in the provision
        uint256 tokens;
        // service provider tokens that are being thawed (and will stop being slashable soon)
        uint256 tokensThawing;
        // shares representing the thawing tokens
        uint256 sharesThawing;
        // max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
        uint32 maxVerifierCut;
        // time, in seconds, tokens must thaw before being withdrawn
        uint64 thawingPeriod;
        uint64 createdAt;
        // max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
        uint32 maxVerifierCutPending;
        // time, in seconds, tokens must thaw before being withdrawn
        uint64 thawingPeriodPending;
    }

    struct ServiceProvider {
        // Tokens on the provider stake (staked by the provider)
        uint256 tokensStaked;
        // tokens used in a provision
        uint256 tokensProvisioned;
    }

    // the new "Indexer" struct
    struct ServiceProviderInternal {
        // Tokens on the Service Provider stake (staked by the provider)
        uint256 tokensStaked;
        // Tokens used in allocations
        uint256 __DEPRECATED_tokensAllocated; // solhint-disable-line graph/leading-underscore
        // Tokens locked for withdrawal subject to thawing period
        uint256 __DEPRECATED_tokensLocked;
        // Block when locked tokens can be withdrawn
        uint256 __DEPRECATED_tokensLockedUntil;
        // tokens used in a provision
        uint256 tokensProvisioned;
    }

    struct DelegationPool {
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        uint256 tokensThawing; // Tokens thawing in the pool
        uint256 sharesThawing; // Shares representing the thawing tokens
    }

    struct DelegationPoolInternal {
        uint32 __DEPRECATED_cooldownBlocks;
        uint32 __DEPRECATED_indexingRewardCut; // in PPM
        uint32 __DEPRECATED_queryFeeCut; // in PPM
        uint256 __DEPRECATED_updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        mapping(address => DelegationInternal) delegators; // Mapping of delegator => Delegation
        uint256 tokensThawing; // Tokens thawing in the pool
        uint256 sharesThawing; // Shares representing the thawing tokens
    }

    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
    }

    struct DelegationInternal {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 __DEPRECATED_tokensLocked; // Tokens locked for undelegation
        uint256 __DEPRECATED_tokensLockedUntil; // Epoch when locked tokens can be withdrawn
    }

    struct ThawRequest {
        // shares that represent the tokens being thawed
        uint256 shares;
        // the timestamp when the thawed funds can be removed from the provision
        uint64 thawingUntil;
        // id of the next thaw request in the linked list
        bytes32 next;
    }
}
