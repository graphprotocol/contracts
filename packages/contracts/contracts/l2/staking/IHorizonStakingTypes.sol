// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

interface IHorizonStakingTypes {
    struct Provision {
        // Service provider that created the provision
        address serviceProvider;
        // tokens in the provision
        uint256 tokens;
        // tokens that are being thawed (and will stop being slashable soon)
        uint256 tokensThawing;
        // timestamp of provision creation
        uint64 createdAt;
        // authority to slash the provision
        address verifier;
        // max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
        uint32 maxVerifierCut;
        // time, in seconds, tokens must thaw before being withdrawn
        uint64 thawingPeriod;
    }

    struct ServiceProvider {
        // Tokens on the provider stake (staked by the provider)
        uint256 tokensStaked;
        // tokens used in a provision
        uint256 tokensProvisioned;
        // tokens that initiated a thawing in any one of the provider's provisions
        uint256 tokensRequestedThaw;
        // tokens that have been removed from any one of the provider's provisions after thawing
        uint256 tokensFulfilledThaw;
        // provisions that take priority for undelegation force thawing
        bytes32[] forceThawProvisions;
    }

    struct DelegationPool {
        uint32 __DEPRECATED_cooldownBlocks; // solhint-disable-line var-name-mixedcase
        uint32 __DEPRECATED_indexingRewardCut; // in PPM
        uint32 __DEPRECATED_queryFeeCut; // in PPM
        uint256 __DEPRECATED_updatedAtBlock; // Block when the pool was last updated
        uint256 tokens; // Total tokens as pool reserves
        uint256 shares; // Total shares minted in the pool
        mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
    }

    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
        uint256 __DEPRECATED_tokensLocked; // Tokens locked for undelegation
        uint256 __DEPRECATED_tokensLockedUntil; // Epoch when locked tokens can be withdrawn
    }

    struct ThawRequest {
        // tokens that are being thawed by this request
        uint256 tokens;
        // the provision id to which this request corresponds to
        bytes32 provisionId;
        // the address that initiated the thaw request, allowed to remove the funds once thawed
        address owner;
        // the timestamp when the thawed funds can be removed from the provision
        uint64 thawingUntil;
        // the value of `ServiceProvider.tokensRequestedThaw` the moment the thaw request is created
        uint256 tokensRequestedThawSnapshot;
    }

    // the new "Indexer" struct
    struct ServiceProviderInternal {
        // Tokens on the Service Provider stake (staked by the provider)
        uint256 tokensStaked;
        // Tokens used in allocations
        uint256 __DEPRECATED_tokensAllocated;
        // Tokens locked for withdrawal subject to thawing period
        uint256 __DEPRECATED_tokensLocked;
        // Block when locked tokens can be withdrawn
        uint256 __DEPRECATED_tokensLockedUntil;
        // tokens used in a provision
        uint256 tokensProvisioned;
        // tokens that initiated a thawing in any one of the provider's provisions
        uint256 tokensRequestedThaw;
        // tokens that have been removed from any one of the provider's provisions after thawing
        uint256 tokensFulfilledThaw;
        // provisions that take priority for undelegation force thawing
        bytes32[] forceThawProvisions;
    }

}
