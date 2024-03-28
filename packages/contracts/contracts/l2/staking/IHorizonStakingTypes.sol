// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

interface IHorizonStakingTypes {
    struct Provision {
        // service provider tokens in the provision
        uint256 tokens;
        // service provider tokens that are being thawed (and will stop being slashable soon)
        uint256 tokensThawing;
        // shares representing the thawing tokens
        uint256 sharesThawing;
        // delegated tokens in the provision
        uint256 delegatedTokens;
        // delegated tokens that are being thawed (and will stop being slashable soon)
        uint256 delegatedTokensThawing;
        // shares that represent the delegated tokens that are being thawed
        uint256 delegatedSharesThawing;
        // max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
        uint32 maxVerifierCut;
        // time, in seconds, tokens must thaw before being withdrawn
        uint64 thawingPeriod;
        bytes32 firstThawRequestId;
        bytes32 lastThawRequestId;
        uint256 nThawRequests;
        // The effective delegator fee cuts for each (data-service-defined) fee type
        // This is in PPM and is the cut taken by the indexer from the fees that correspond to delegators
        // (based on stake vs delegated stake proportion).
        // The cuts are applied in GraphPayments so apply to all data services that use it.
        uint32[] delegationFeeCuts;
    }

    struct ServiceProvider {
        // Tokens on the provider stake (staked by the provider)
        uint256 tokensStaked;
        // tokens used in a provision
        uint256 tokensProvisioned;
        // Next nonce to be used to generate thaw request IDs
        uint256 nextThawRequestNonce;
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
        bytes32 firstThawRequestId;
        bytes32 lastThawRequestId;
        uint256 nThawRequests;
        uint256 nextThawRequestNonce;
    }

    struct ThawRequest {
        // shares that represent the tokens being thawed
        uint256 shares;
        // the timestamp when the thawed funds can be removed from the provision
        uint64 thawingUntil;
        // id of the next thaw request in the linked list
        bytes32 next;
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
        // Next nonce to be used to generate thaw request IDs
        uint256 nextThawRequestNonce;
    }
}
