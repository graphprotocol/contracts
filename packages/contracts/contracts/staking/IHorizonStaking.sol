// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

interface IHorizonStaking {
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
        // shares owned by the delegator in the pool
        uint256 shares;
        // tokens delegated to the pool
        uint256 tokens;
        // Timestamp when locked tokens can be undelegated (after the timelock)
        uint256 tokensLockedUntil;
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

    // whitelist/deny a verifier
    function allowVerifier(address verifier, bool allow) external;

    // deposit stake
    function stake(uint256 tokens) external;

    // create a provision
    function provision(uint256 tokens, address verifier, uint256 maxVerifierCut, uint256 thawingPeriod) external;

    // initiate a thawing to remove tokens from a provision
    function thaw(bytes32 provisionId, uint256 tokens) external returns (bytes32 thawRequestId);

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(bytes32 thawRequestId) external;

    // moves thawed stake from one provision into another provision
    function reprovision(bytes32 thawRequestId, bytes32 provisionId) external;

    // moves thawed stake back to the owner's account - stake is removed from the protocol
    function withdraw(bytes32 thawRequestId) external;

    // delegate tokens to a provider
    function delegate(address serviceProvider, uint256 tokens) external;

    // undelegate tokens
    function undelegate(
        address serviceProvider,
        uint256 tokens,
        bytes32[] calldata provisions
    ) external returns (bytes32 thawRequestId);

    // slash a service provider
    function slash(bytes32 provisionId, uint256 tokens, uint256 verifierAmount) external;

    // set the Service Provider's preferred provisions to be force thawed
    function setForceThawProvisions(bytes32[] calldata provisions) external;

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked + DelegationPool.serviceProvider.tokens`
    function getStake(address serviceProvider) external view returns (uint256 tokens);

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) external view returns (uint256 tokens);

    // staked tokens the provider can provision before hitting the delegation cap
    // `ServiceProvider.tokensStaked * Staking.delegationRatio - Provision.tokensProvisioned`
    function getCapacity(address serviceProvider) external view returns (uint256 tokens);

    // provisioned tokens that are not being used
    // `Provision.tokens - Provision.tokensThawing`
    function getTokensAvailable(bytes32 provision) external view returns (uint256 tokens);

    function getServiceProvider(address serviceProvider) external view returns (ServiceProvider memory);

    function getProvision(address serviceProvider, address verifier) external view returns (Provision memory);

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @param _operator The address to check for auth
     * @param _serviceProvider The service provider on behalf of whom they're claiming to act
     * @param _verifier The verifier / data service on which they're claiming to act
     */
    function isAuthorized(address _operator, address _serviceProvider, address _verifier) external view returns (bool);
}
