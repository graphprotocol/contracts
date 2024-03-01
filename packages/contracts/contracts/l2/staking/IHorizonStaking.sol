// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

import { IHorizonStakingTypes } from "./IHorizonStakingTypes.sol";

interface IHorizonStaking is IHorizonStakingTypes {
    /**
     * @dev Emitted when serviceProvider allows a verifier
     */
    event VerifierAllowed(address indexed serviceProvider, address indexed verifier);

    /**
     * @dev Emitted when serviceProvider denies a verifier
     */
    event VerifierDenied(address indexed serviceProvider, address indexed verifier);

    /**
     * @dev Emitted when an operator is allowed or denied by a service provider
     */
    event SetOperator(address indexed serviceProvider, address indexed operator, bool allowed);

    // whitelist/deny a verifier
    function allowVerifier(address _verifier) external;
    function denyVerifier(address _verifier) external;

    // deposit stake
    function stake(uint256 _tokens) external;
    function stakeTo(address _serviceProvider, uint256 _tokens) external;

    // create a provision
    function provision(
        uint256 _tokens,
        address _verifier,
        uint256 _maxVerifierCut,
        uint256 _thawingPeriod
    ) external;

    // initiate a thawing to remove tokens from a provision
    function thaw(bytes32 _provisionId, uint256 _tokens) external returns (bytes32);

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(bytes32 _thawRequestId) external;

    // moves thawed stake from one provision into another provision
    function reprovision(bytes32 _thawRequestId, bytes32 _provisionId) external;

    // moves thawed stake back to the owner's account - stake is removed from the protocol
    function withdraw(bytes32 _thawRequestId) external;

    // delegate tokens to a provider
    function delegate(address _serviceProvider, uint256 _tokens) external;

    // undelegate tokens
    function undelegate(
        address _serviceProvider,
        uint256 _tokens,
        bytes32[] calldata _provisions
    ) external returns (bytes32[] memory);

    // slash a service provider
    function slash(
        bytes32 _provisionId,
        uint256 _tokens,
        uint256 _verifierAmount
    ) external;

    // set the Service Provider's preferred provisions to be force thawed
    function setForceThawProvisions(bytes32[] calldata _provisions) external;

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked + DelegationPool.serviceProvider.tokens`
    function getStake(address _serviceProvider) external view returns (uint256 tokens);

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address _serviceProvider) external view returns (uint256 tokens);

    // staked tokens the provider can provision before hitting the delegation cap
    // `ServiceProvider.tokensStaked * Staking.delegationRatio - Provision.tokensProvisioned`
    function getCapacity(address _serviceProvider) external view returns (uint256);

    // provisioned tokens that are not being used
    // `Provision.tokens - Provision.tokensThawing`
    function getTokensAvailable(bytes32 _provisionId) external view returns (uint256 tokens);

    function getServiceProvider(address _serviceProvider)
        external
        view
        returns (ServiceProvider memory);

    function getProvision(bytes32 _provisionId) external view returns (Provision memory);

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller.
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, bool _allowed) external;
}
