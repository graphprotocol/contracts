// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

/* solhint-disable var-name-mixedcase */ // TODO: create custom var-name-mixedcase

/**
 * @title Defines the data types used in the Horizon staking contract
 * @dev In order to preserve storage compatibility some data structures keep deprecated fields.
 * These structures have then two representations, an internal one used by the contract storage and a public one.
 * Getter functions should retrieve internal representations, remove deprecated fields and return the public representation.
 */
interface IHorizonStakingTypes {
    /**
     * @notice Represents stake assigned to a specific verifier/data service.
     * Provisioned stake is locked and can be used as economic security by a data service.
     */
    struct Provision {
        // Service provider tokens in the provision (does not include delegated tokens)
        uint256 tokens;
        // Service provider tokens that are being thawed (and will stop being slashable soon)
        uint256 tokensThawing;
        // Shares representing the thawing tokens
        uint256 sharesThawing;
        // Max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
        uint32 maxVerifierCut;
        // Time, in seconds, tokens must thaw before being withdrawn
        uint64 thawingPeriod;
        // Timestamp when the provision was created
        uint64 createdAt;
        // Pending value for `maxVerifierCut`. Verifier needs to accept it before it becomes active.
        uint32 maxVerifierCutPending;
        // Pending value for `thawingPeriod`. Verifier needs to accept it before it becomes active.
        uint64 thawingPeriodPending;
    }

    /**
     * @notice Public representation of a service provider.
     * @dev See {ServiceProviderInternal} for the actual storage representation
     */
    struct ServiceProvider {
        // Total amount of tokens on the provider stake (only staked by the provider, inludes all provisions)
        uint256 tokensStaked;
        // Total amount of tokens locked in provisions (only staked by the provider)
        uint256 tokensProvisioned;
    }

    /**
     * @notice Internal representation of a service provider.
     * @dev It contains deprecated fields from the `Indexer` struct to maintain storage compatibility.
     */
    struct ServiceProviderInternal {
        // Total amount of tokens on the provider stake (only staked by the provider, inludes all provisions)
        uint256 tokensStaked;
        // (Deprecated) Tokens used in allocations
        uint256 __DEPRECATED_tokensAllocated; // solhint-disable-line graph/leading-underscore
        // (Deprecated) Tokens locked for withdrawal subject to thawing period
        uint256 __DEPRECATED_tokensLocked;
        // (Deprecated) Block when locked tokens can be withdrawn
        uint256 __DEPRECATED_tokensLockedUntil;
        // Total amount of tokens locked in provisions (only staked by the provider)
        uint256 tokensProvisioned;
    }

    /**
     * @notice Public representation of a delegation pool.
     * @dev See {DelegationPoolInternal} for the actual storage representation
     */
    struct DelegationPool {
        // Total tokens as pool reserves
        uint256 tokens;
        // Total shares minted in the pool
        uint256 shares;
        // Tokens thawing in the pool
        uint256 tokensThawing;
        // Shares representing the thawing tokens
        uint256 sharesThawing;
    }

    /**
     * @notice Internal representation of a delegation pool.
     * @dev It contains deprecated fields from the previous version of the `DelegationPool` struct
     * to maintain storage compatibility.
     */
    struct DelegationPoolInternal {
        // (Deprecated) Time, in blocks, an indexer must wait before updating delegation parameters
        uint32 __DEPRECATED_cooldownBlocks;
        // (Deprecated) Percentage of indexing rewards for the delegation pool, in PPM
        uint32 __DEPRECATED_indexingRewardCut;
        // (Deprecated) Percentage of query fees for the delegation pool, in PPM
        uint32 __DEPRECATED_queryFeeCut;
        // (Deprecated) Block when the delegation parameters were last updated
        uint256 __DEPRECATED_updatedAtBlock;
        // Total tokens as pool reserves
        uint256 tokens;
        // Total shares minted in the pool
        uint256 shares;
        // Delegation details by delegator
        mapping(address delegator => DelegationInternal delegation) delegators;
        // Tokens thawing in the pool
        uint256 tokensThawing;
        // Shares representing the thawing tokens
        uint256 sharesThawing;
    }

    /**
     * @notice Public representation of delegation details.
     * @dev See {DelegationInternal} for the actual storage representation
     */
    struct Delegation {
        uint256 shares; // Shares owned by a delegator in the pool
    }

    /**
     * @notice Internal representation of delegation details.
     * @dev It contains deprecated fields from the previous version of the `Delegation` struct
     * to maintain storage compatibility.
     */
    struct DelegationInternal {
        // Shares owned by the delegator in the pool
        uint256 shares;
        // (Deprecated) Tokens locked for undelegation
        uint256 __DEPRECATED_tokensLocked;
        // (Deprecated) Epoch when locked tokens can be withdrawn
        uint256 __DEPRECATED_tokensLockedUntil;
    }

    /**
     * @notice Details of a stake thawing operation.
     * @dev ThawRequests are stored in linked lists by service provider/delegator,
     * ordered by creation timestamp.
     */
    struct ThawRequest {
        // Shares that represent the tokens being thawed
        uint256 shares;
        // The timestamp when the thawed funds can be removed from the provision
        uint64 thawingUntil;
        // Id of the next thaw request in the linked list
        bytes32 next;
    }
}
