// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IHorizonStaking } from "./IHorizonStaking.sol";
import { L2StakingBackwardsCompatibility } from "./L2StakingBackwardsCompatibility.sol";
import { TokenUtils } from "../../utils/TokenUtils.sol";
import { MathUtils } from "../../staking/libs/MathUtils.sol";

contract HorizonStaking is L2StakingBackwardsCompatibility, IHorizonStaking {
    using SafeMath for uint256;

    /// Maximum value that can be set as the maxVerifierCut in a provision.
    /// It is equivalent to 50% in parts-per-million, to protect delegators from
    /// service providers using a malicious verifier.
    uint32 public constant MAX_MAX_VERIFIER_CUT = 500000; // 50%

    /**
     * @notice Allow verifier for stake provisions.
     * After calling this, and a timelock period, the service provider will
     * be allowed to provision stake that is slashable by the verifier.
     * @param _verifier The address of the contract that can slash the provision
     */
    function allowVerifier(address _verifier) external override {
        require(_verifier != address(0), "!verifier");
        require(verifierAllowlist[msg.sender][_verifier] == 0, "verifier already allowed");
        verifierAllowlist[msg.sender][_verifier] = block.timestamp;
        emit VerifierAllowed(msg.sender, _verifier);
    }

    /**
     * @notice Deny a verifier for stake provisions.
     * After calling this, the service provider will immediately
     * be unable to provision any stake to the verifier.
     * Any existing provisions will be unaffected.
     * @param _verifier The address of the contract that can slash the provision
     */
    function denyVerifier(address _verifier) external override {
        require(verifierAllowlist[msg.sender][_verifier] > 0, "verifier not allowed");
        verifierAllowlist[msg.sender][_verifier] = 0;
        emit VerifierDenied(msg.sender, _verifier);
    }

    /**
     * @notice Deposit tokens on the caller's stake.
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external override {
        stakeTo(msg.sender, _tokens);
    }

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider.
     * @param _serviceProvider Address of the indexer
     * @param _tokens Amount of tokens to stake
     */
    function stakeTo(address _serviceProvider, uint256 _tokens) public override notPartialPaused {
        require(_tokens > 0, "!tokens");

        // Transfer tokens to stake from caller to this contract
        TokenUtils.pullTokens(graphToken(), msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_serviceProvider, _tokens);
    }

    // create a provision
    function provision(
        address _serviceProvider,
        uint256 _tokens,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) external override returns (bytes32) {
        require(_isAuth(_serviceProvider), "!auth");
        require(_tokens > 0, "!tokens");
        require(getCapacity(_serviceProvider) >= _tokens, "insufficient capacity");
        require(_maxVerifierCut <= MAX_MAX_VERIFIER_CUT, "maxVerifierCut too high");
        require(_thawingPeriod <= maxThawingPeriod, "thawingPeriod too high");
        require(verifierAllowlist[_serviceProvider][_verifier] > 0, "verifier not allowed");
        require(
            block.timestamp >= verifierAllowlist[_serviceProvider][_verifier].add(verifierTimelock),
            "verifier timelock"
        );

        return
            _createProvision(_serviceProvider, _tokens, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    // add more tokens from idle stake to an existing provision
    function addToProvision(bytes32 _provisionId, uint256 _tokens) external override {
        Provision storage prov = provisions[_provisionId];
        address serviceProvider = prov.serviceProvider;
        require(_isAuth(serviceProvider), "!auth");
        require(_tokens > 0, "!tokens");
        require(getCapacity(serviceProvider) >= _tokens, "insufficient capacity");

        prov.tokens = prov.tokens.add(_tokens);
        __serviceProviders[serviceProvider].tokensProvisioned = __serviceProviders[serviceProvider]
            .tokensProvisioned
            .add(_tokens);
        emit ProvisionIncreased(_provisionId, _tokens);
    }

    // initiate a thawing to remove tokens from a provision
    function thaw(bytes32 provisionId, uint256 tokens) external override returns (bytes32) {
        // TODO
        return bytes32(0);
    }

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(bytes32 thawRequestId) external override {
        // TODO
    }

    // moves thawed stake from one provision into another provision
    function reprovision(bytes32 thawRequestId, bytes32 provisionId) external override {
        // TODO
    }

    // moves thawed stake back to the owner's account - stake is removed from the protocol
    function withdraw(bytes32 thawRequestId) external override {
        // TODO
    }

    // delegate tokens to a provider
    function delegate(address serviceProvider, uint256 tokens) external override {
        // TODO
    }

    // undelegate tokens
    function undelegate(
        address serviceProvider,
        uint256 tokens,
        bytes32[] calldata provisions
    ) external override returns (bytes32[] memory) {
        // TODO
        bytes32[] memory thawRequests;
        return thawRequests;
    }

    // slash a service provider
    function slash(
        bytes32 provisionId,
        uint256 tokens,
        uint256 verifierAmount
    ) external override {
        // TODO
    }

    // set the Service Provider's preferred provisions to be force thawed
    function setForceThawProvisions(bytes32[] calldata provisions) external override {}

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked + DelegationPool.serviceProvider.tokens`
    function getStake(address serviceProvider) public view override returns (uint256 tokens) {
        return
            __serviceProviders[serviceProvider].tokensStaked.add(
                __delegationPools[serviceProvider].tokens
            );
    }

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) public view override returns (uint256 tokens) {
        return getStake(serviceProvider).sub(__serviceProviders[serviceProvider].tokensProvisioned);
    }

    // staked tokens the provider can provision before hitting the delegation cap
    // `ServiceProvider.tokensStaked * Staking.delegationRatio - ServiceProvider.tokensProvisioned`
    function getCapacity(address _serviceProvider) public view override returns (uint256) {
        return
            MathUtils
                .min(
                    getStake(_serviceProvider),
                    __serviceProviders[_serviceProvider].tokensStaked.mul(
                        uint256(__delegationRatio).add(1)
                    )
                )
                .sub(__serviceProviders[_serviceProvider].tokensProvisioned);
    }

    // provisioned tokens that are not being used
    // `Provision.tokens - Provision.tokensThawing`
    function getTokensAvailable(bytes32 _provisionId) public view override returns (uint256) {
        return provisions[_provisionId].tokens.sub(provisions[_provisionId].tokensThawing);
    }

    function getServiceProvider(address serviceProvider)
        public
        view
        override
        returns (ServiceProvider memory)
    {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = __serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        sp.tokensRequestedThaw = spInternal.tokensRequestedThaw;
        sp.tokensFulfilledThaw = spInternal.tokensFulfilledThaw;
        sp.forceThawProvisions = spInternal.forceThawProvisions;
        return sp;
    }

    function getProvision(bytes32 _provisionId) public view override returns (Provision memory) {
        return provisions[_provisionId];
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller.
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        __operatorAuth[msg.sender][_operator] = _allowed;
        emit SetOperator(msg.sender, _operator, _allowed);
    }

    /**
     * @dev Creates a provision
     */
    function _createProvision(
        address _serviceProvider,
        uint256 _tokens,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) internal returns (bytes32) {
        ServiceProviderInternal storage sp = __serviceProviders[_serviceProvider];
        bytes32 provisionId = keccak256(abi.encodePacked(_serviceProvider, sp.nextProvisionNonce));
        ++sp.nextProvisionNonce;
        provisions[provisionId] = Provision({
            serviceProvider: _serviceProvider,
            tokens: _tokens,
            tokensThawing: 0,
            createdAt: uint64(block.timestamp),
            verifier: _verifier,
            maxVerifierCut: _maxVerifierCut,
            thawingPeriod: _thawingPeriod
        });
        sp.tokensProvisioned = sp.tokensProvisioned.add(_tokens);

        emit ProvisionCreated(
            provisionId,
            _serviceProvider,
            _tokens,
            _verifier,
            _maxVerifierCut,
            _thawingPeriod
        );
    }
}
