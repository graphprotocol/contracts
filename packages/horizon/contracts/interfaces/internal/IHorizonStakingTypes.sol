// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

/**
 * @title Defines the data types used in the Horizon staking contract
 * @dev In order to preserve storage compatibility some data structures keep deprecated fields.
 * These structures have then two representations, an internal one used by the contract storage and a public one.
 * Getter functions should retrieve internal representations, remove deprecated fields and return the public representation.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IHorizonStakingTypes {
    /**
     * @notice Represents stake assigned to a specific verifier/data service.
     * Provisioned stake is locked and can be used as economic security by a data service.
     * @param tokens Service provider tokens in the provision (does not include delegated tokens)
     * @param tokensThawing Service provider tokens that are being thawed (and will stop being slashable soon)
     * @param sharesThawing Shares representing the thawing tokens
     * @param maxVerifierCut Max amount that can be taken by the verifier when slashing, expressed in parts-per-million of the amount slashed
     * @param thawingPeriod Time, in seconds, tokens must thaw before being withdrawn
     * @param createdAt Timestamp when the provision was created
     * @param maxVerifierCutPending Pending value for `maxVerifierCut`. Verifier needs to accept it before it becomes active.
     * @param thawingPeriodPending Pending value for `thawingPeriod`. Verifier needs to accept it before it becomes active.
     * @param thawingNonce Value of the current thawing nonce. Thaw requests with older nonces are invalid.
     */
    struct Provision {
        uint256 tokens;
        uint256 tokensThawing;
        uint256 sharesThawing;
        uint32 maxVerifierCut;
        uint64 thawingPeriod;
        uint64 createdAt;
        uint32 maxVerifierCutPending;
        uint64 thawingPeriodPending;
        uint256 thawingNonce;
    }

    /**
     * @notice Public representation of a service provider.
     * @dev See {ServiceProviderInternal} for the actual storage representation
     * @param tokensStaked Total amount of tokens on the provider stake (only staked by the provider, includes all provisions)
     * @param tokensProvisioned Total amount of tokens locked in provisions (only staked by the provider)
     */
    struct ServiceProvider {
        uint256 tokensStaked;
        uint256 tokensProvisioned;
    }

    /**
     * @notice Internal representation of a service provider.
     * @dev It contains deprecated fields from the `Indexer` struct to maintain storage compatibility.
     * @param tokensStaked Total amount of tokens on the provider stake (only staked by the provider, includes all provisions)
     * @param __DEPRECATED_tokensAllocated (Deprecated) Tokens used in allocations
     * @param __DEPRECATED_tokensLocked (Deprecated) Tokens locked for withdrawal subject to thawing period
     * @param __DEPRECATED_tokensLockedUntil (Deprecated) Block when locked tokens can be withdrawn
     * @param tokensProvisioned Total amount of tokens locked in provisions (only staked by the provider)
     */
    struct ServiceProviderInternal {
        uint256 tokensStaked;
        uint256 __DEPRECATED_tokensAllocated;
        uint256 __DEPRECATED_tokensLocked;
        uint256 __DEPRECATED_tokensLockedUntil;
        uint256 tokensProvisioned;
    }

    /**
     * @notice Public representation of a delegation pool.
     * @dev See {DelegationPoolInternal} for the actual storage representation
     * @param tokens Total tokens as pool reserves
     * @param shares Total shares minted in the pool
     * @param tokensThawing Tokens thawing in the pool
     * @param sharesThawing Shares representing the thawing tokens
     * @param thawingNonce Value of the current thawing nonce. Thaw requests with older nonces are invalid.
     */
    struct DelegationPool {
        uint256 tokens;
        uint256 shares;
        uint256 tokensThawing;
        uint256 sharesThawing;
        uint256 thawingNonce;
    }

    /**
     * @notice Internal representation of a delegation pool.
     * @dev It contains deprecated fields from the previous version of the `DelegationPool` struct
     * to maintain storage compatibility.
     * @param __DEPRECATED_cooldownBlocks (Deprecated) Time, in blocks, an indexer must wait before updating delegation parameters
     * @param __DEPRECATED_indexingRewardCut (Deprecated) Percentage of indexing rewards for the service provider, in PPM
     * @param __DEPRECATED_queryFeeCut (Deprecated) Percentage of query fees for the service provider, in PPM
     * @param __DEPRECATED_updatedAtBlock (Deprecated) Block when the delegation parameters were last updated
     * @param tokens Total tokens as pool reserves
     * @param shares Total shares minted in the pool
     * @param delegators Delegation details by delegator
     * @param tokensThawing Tokens thawing in the pool
     * @param sharesThawing Shares representing the thawing tokens
     * @param thawingNonce Value of the current thawing nonce. Thaw requests with older nonces are invalid.
     */
    struct DelegationPoolInternal {
        uint32 __DEPRECATED_cooldownBlocks;
        uint32 __DEPRECATED_indexingRewardCut;
        uint32 __DEPRECATED_queryFeeCut;
        uint256 __DEPRECATED_updatedAtBlock;
        uint256 tokens;
        uint256 shares;
        mapping(address delegator => DelegationInternal delegation) delegators;
        uint256 tokensThawing;
        uint256 sharesThawing;
        uint256 thawingNonce;
    }

    /**
     * @notice Public representation of delegation details.
     * @dev See {DelegationInternal} for the actual storage representation
     * @param shares Shares owned by a delegator in the pool
     */
    struct Delegation {
        uint256 shares;
    }

    /**
     * @notice Internal representation of delegation details.
     * @dev It contains deprecated fields from the previous version of the `Delegation` struct
     * to maintain storage compatibility.
     * @param shares Shares owned by the delegator in the pool
     * @param __DEPRECATED_tokensLocked Tokens locked for undelegation
     * @param __DEPRECATED_tokensLockedUntil Epoch when locked tokens can be withdrawn
     */
    struct DelegationInternal {
        uint256 shares;
        uint256 __DEPRECATED_tokensLocked;
        uint256 __DEPRECATED_tokensLockedUntil;
    }

    /**
     * @dev Enum to specify the type of thaw request.
     * @param Provision Represents a thaw request for a provision.
     * @param Delegation Represents a thaw request for a delegation.
     */
    enum ThawRequestType {
        Provision,
        Delegation
    }

    /**
     * @notice Details of a stake thawing operation.
     * @dev ThawRequests are stored in linked lists by service provider/delegator,
     * ordered by creation timestamp.
     * @param shares Shares that represent the tokens being thawed
     * @param thawingUntil The timestamp when the thawed funds can be removed from the provision
     * @param next Id of the next thaw request in the linked list
     * @param thawingNonce Used to invalidate unfulfilled thaw requests
     */
    struct ThawRequest {
        uint256 shares;
        uint64 thawingUntil;
        bytes32 next;
        uint256 thawingNonce;
    }

    /**
     * @notice Parameters to fulfill thaw requests.
     * @dev This struct is used to avoid stack too deep error in the `fulfillThawRequests` function.
     * @param requestType The type of thaw request (Provision or Delegation)
     * @param serviceProvider The address of the service provider
     * @param verifier The address of the verifier
     * @param owner The address of the owner of the thaw request
     * @param tokensThawing The current amount of tokens already thawing
     * @param sharesThawing The current amount of shares already thawing
     * @param nThawRequests The number of thaw requests to fulfill. If set to 0, all thaw requests are fulfilled.
     * @param thawingNonce The current valid thawing nonce. Any thaw request with a different nonce is invalid and should be ignored.
     */
    struct FulfillThawRequestsParams {
        ThawRequestType requestType;
        address serviceProvider;
        address verifier;
        address owner;
        uint256 tokensThawing;
        uint256 sharesThawing;
        uint256 nThawRequests;
        uint256 thawingNonce;
    }

    /**
     * @notice Results of the traversal of thaw requests.
     * @dev This struct is used to avoid stack too deep error in the `fulfillThawRequests` function.
     * @param requestsFulfilled The number of thaw requests fulfilled
     * @param tokensThawed The total amount of tokens thawed
     * @param tokensThawing The total amount of tokens thawing
     * @param sharesThawing The total amount of shares thawing
     */
    struct TraverseThawRequestsResults {
        uint256 requestsFulfilled;
        uint256 tokensThawed;
        uint256 tokensThawing;
        uint256 sharesThawing;
    }
}
