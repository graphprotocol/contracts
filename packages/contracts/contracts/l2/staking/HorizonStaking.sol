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

    /// Minimum size of a provision
    uint256 public constant MIN_PROVISION_SIZE = 1e18;

    /// Maximum number of simultaneous stake thaw requests or undelegations
    uint256 public constant MAX_THAW_REQUESTS = 100;

    constructor(address _subgraphDataServiceAddress) L2StakingBackwardsCompatibility(_subgraphDataServiceAddress) {}

    /**
     * @notice Allow verifier for stake provisions.
     * After calling this, and a timelock period, the service provider will
     * be allowed to provision stake that is slashable by the verifier.
     * @param _verifier The address of the contract that can slash the provision
     */
    function allowVerifier(address _verifier) external override {
        require(_verifier != address(0), "!verifier");
        require(!verifierAllowlist[msg.sender][_verifier], "verifier already allowed");
        verifierAllowlist[msg.sender][_verifier] = true;
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
        require(verifierAllowlist[msg.sender][_verifier], "verifier not allowed");
        verifierAllowlist[msg.sender][_verifier] = false;
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
        address _verifier,
        uint256 _tokens,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) external override {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(_tokens >= MIN_PROVISION_SIZE, "!tokens");
        require(getIdleStake(_serviceProvider) >= _tokens, "insufficient capacity");
        require(_maxVerifierCut <= MAX_MAX_VERIFIER_CUT, "maxVerifierCut too high");
        require(_thawingPeriod <= maxThawingPeriod, "thawingPeriod too high");
        require(verifierAllowlist[_serviceProvider][_verifier], "verifier not allowed");

        return
            _createProvision(_serviceProvider, _tokens, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    // add more tokens from idle stake to an existing provision
    function addToProvision(address _serviceProvider, address _verifier, uint256 _tokens) external override {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        _addToProvision(_serviceProvider, _verifier, _tokens);
    }

    // initiate a thawing to remove tokens from a provision
    function thaw(address _serviceProvider, address _verifier, uint256 _tokens) external override returns (bytes32) {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(_tokens > 0, "!tokens");
        Provision storage prov = provisions[_serviceProvider][_verifier];
        ServiceProviderInternal storage serviceProvider = serviceProviders[_serviceProvider];
        bytes32 thawRequestId = keccak256(abi.encodePacked(_serviceProvider, _verifier, serviceProvider.nextThawRequestNonce));
        serviceProvider.nextThawRequestNonce += 1;
        ThawRequest storage thawRequest = thawRequests[thawRequestId];

        require(getTokensAvailable(_serviceProvider, _verifier) >= _tokens, "insufficient tokens available");
        prov.tokensThawing = prov.tokensThawing.add(_tokens);

        thawRequest.shares = prov.sharesThawing.mul(_tokens).div(prov.tokensThawing);
        thawRequest.thawingUntil = uint64(block.timestamp).add(prov.thawingPeriod);
        prov.sharesThawing = prov.sharesThawing.add(thawRequest.shares);

        require(prov.nThawRequests < MAX_THAW_REQUESTS, "max thaw requests");
        if (prov.nThawRequests == 0) {
            prov.firstThawRequest = thawRequestId;
        } else {
            thawRequests[prov.lastThawRequest].next = thawRequestId;
        }
        prov.lastThawRequest = thawRequestId;
        prov.nThawRequests += 1;

        emit ProvisionThawInitiated(_serviceProvider, _verifier, _tokens, thawRequest.thawingUntil, thawRequestId);

        return thawRequestId;
    }

    /**
     * @notice Get the amount of service provider's tokens in a provision that have finished thawing
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     */
    function getThawedTokens(address _serviceProvider, address _verifier) external view override returns (uint256) {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        if (prov.nThawRequests == 0) {
            return 0;
        }
        bytes32 thawRequestId = prov.firstThawRequest;
        uint256 tokens = 0;
        while (thawRequestId != bytes32(0)) {
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            if (thawRequest.thawingUntil <= block.timestamp) {
                tokens += thawRequest.shares.mul(prov.tokensThawing).div(prov.sharesThawing);
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }
        return tokens;
    }

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(address _serviceProvider, address _verifier, uint256 _tokens) external override {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(_tokens > 0, "!tokens");
        ServiceProviderInternal storage serviceProvider = serviceProviders[_serviceProvider];
        _fulfillThawRequests(_serviceProvider, _verifier, _tokens);
        serviceProvider.tokensProvisioned = serviceProvider.tokensProvisioned.sub(_tokens);
    }

    // moves thawed stake from one provision into another provision
    function reprovision(address _serviceProvider, address _oldVerifier, address _newVerifier, uint256 _tokens) external override {
        require(isAuthorized(msg.sender, _serviceProvider, _oldVerifier), "!auth");
        require(isAuthorized(msg.sender, _serviceProvider, _newVerifier), "!auth");
        require(_tokens > 0, "!tokens");

        _fulfillThawRequests(_serviceProvider, _oldVerifier, _tokens);
        _addToProvision(_serviceProvider, _newVerifier, _tokens);
    }

    // moves idle stake back to the owner's account - stake is removed from the protocol
    // global operators are allowed to call this but stake is always sent to the service provider's address
    function withdraw(address _serviceProvider, uint256 _tokens) external override {
        require(isGlobalAuthorized(msg.sender, _serviceProvider), "!auth");
        require(_tokens > 0, "!tokens");
        require(getIdleStake(_serviceProvider) >= _tokens, "insufficient idle stake");

        serviceProviders[_serviceProvider].tokensStaked = serviceProviders[_serviceProvider].tokensStaked.sub(_tokens);
        TokenUtils.pushTokens(graphToken(), _serviceProvider, _tokens);
    }

    // slash a service provider
    // (called by a verifier)
    function slash(
        address _serviceProvider,
        uint256 _tokens,
        uint256 _verifierCutAmount,
        address _verifierCutDestination
    ) external override {
        address verifier = msg.sender;
        Provision storage prov = provisions[_serviceProvider][verifier];
        require(prov.tokens >= _tokens, "insufficient tokens in provision");

        uint256 tokensToSlash = _tokens;

        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        require(prov.tokens.mul(prov.maxVerifierCut).div(1e6) >= _verifierCutAmount, "verifier cut too high");
        if (_verifierCutAmount > 0) {
            TokenUtils.pushTokens(graphToken(), _verifierCutDestination, _verifierCutAmount);
        }
        if (providerTokensSlashed > 0) {
            TokenUtils.burnTokens(graphToken(), providerTokensSlashed);
            uint256 provisionFractionSlashed = providerTokensSlashed.mul(1e18).div(prov.tokens);
            // TODO check for rounding issues
            prov.tokensThawing = prov.tokensThawing.mul(1e18 - provisionFractionSlashed).div(1e18);
            prov.tokens = prov.tokens.sub(providerTokensSlashed);
            serviceProviders[_serviceProvider].tokensProvisioned = serviceProviders[_serviceProvider].tokensProvisioned.sub(providerTokensSlashed);
            serviceProviders[_serviceProvider].tokensStaked = serviceProviders[_serviceProvider].tokensStaked.sub(providerTokensSlashed);
        }

        tokensToSlash = tokensToSlash.sub(providerTokensSlashed);
        if (tokensToSlash > 0) {
            prov.delegatedTokens = prov.delegatedTokens.sub(tokensToSlash);
            prov.delegatedTokensThawing = prov.delegatedTokensThawing.mul(1e18 - tokensToSlash.mul(1e18).div(prov.delegatedTokens)).div(1e18);
        }
    }

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked + DelegationPool.serviceProvider.tokens`
    function getStake(address serviceProvider) public view override returns (uint256 tokens) {
        return
            serviceProviders[serviceProvider].tokensStaked;
    }

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) public view override returns (uint256 tokens) {
        return serviceProviders[serviceProvider].tokensStaked.sub(serviceProviders[serviceProvider].tokensProvisioned);
    }

    // provisioned tokens that are not being used
    // `Provision.tokens - Provision.tokensThawing`
    function getTokensAvailable(address _serviceProvider, address _verifier) public view override returns (uint256) {
        return provisions[_serviceProvider][_verifier].tokens.sub(provisions[_serviceProvider][_verifier].tokensThawing);
    }

    function getServiceProvider(address serviceProvider)
        public
        view
        override
        returns (ServiceProvider memory)
    {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        sp.nextThawRequestNonce = spInternal.nextThawRequestNonce;
        return sp;
    }

    function getProvision(address _serviceProvider, address _verifier) public view override returns (Provision memory) {
        return provisions[_serviceProvider][_verifier];
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param _operator Address to authorize or unauthorize
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, address _verifier, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        if (_verifier == subgraphDataServiceAddress) {
            legacyOperatorAuth[msg.sender][_operator] = _allowed;
        } else {
            operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        }
        emit OperatorSet(msg.sender, _operator, _verifier, _allowed);
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on all data services.
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function setGlobalOperator(address _operator, address _verifier, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        globalOperatorAuth[msg.sender][_operator] = _allowed;
        emit GlobalOperatorSet(msg.sender, _operator, _allowed);
    }

    /**
     * @notice Check if an operator is authorized for the caller on all their allowlisted verifiers and global stake.
     * @param _operator The address to check for auth
     * @param _serviceProvider The service provider on behalf of whom they're claiming to act
     */
    function isGlobalAuthorized(address _operator, address _serviceProvider) public view override returns (bool) {
        return _operator == _serviceProvider || globalOperatorAuth[_serviceProvider][_operator];
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
        ServiceProviderInternal storage sp = serviceProviders[_serviceProvider];
        provisions[_serviceProvider][_verifier] = Provision({
            serviceProvider: _serviceProvider,
            tokens: _tokens,
            sharesThawing: 0,
            tokensThawing: 0,
            createdAt: uint64(block.timestamp),
            verifier: _verifier,
            maxVerifierCut: _maxVerifierCut,
            thawingPeriod: _thawingPeriod
        });
        sp.tokensProvisioned = sp.tokensProvisioned.add(_tokens);

        emit ProvisionCreated(
            _serviceProvider,
            _verifier,
            _tokens,
            _maxVerifierCut,
            _thawingPeriod
        );
    }

    function _fulfillThawRequests(address _serviceProvider, address _verifier, uint256 _tokens) internal {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        uint256 tokensRemaining = _tokens;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;
        while (tokensRemaining > 0) {
            require(prov.nThawRequests > 0, "not enough thawed tokens");
            bytes32 thawRequestId = prov.firstThawRequest;
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            require(thawRequest.thawingUntil <= block.timestamp, "thawing period not over");
            uint256 thawRequestTokens = thawRequest.shares.mul(tokensThawing).div(sharesThawing);
            if (thawRequestTokens <= tokensRemaining) {
                tokensRemaining = tokensRemaining.sub(thawRequestTokens);
                delete thawRequests[thawRequestId];
                prov.firstThawRequest = thawRequest.next;
                prov.nThawRequests -= 1;
                tokensThawing = tokensThawing.sub(thawRequestTokens);
                sharesThawing = sharesThawing.sub(thawRequest.shares);
            } else {
                // TODO check for potential rounding issues
                uint256 sharesRemoved = tokensRemaining.mul(prov.sharesThawing).div(prov.tokensThawing);
                thawRequest.shares = thawRequest.shares.sub(sharesRemoved);
                tokensThawing = tokensThawing.sub(tokensRemaining);
                sharesThawing = sharesThawing.sub(sharesRemoved);
            }
            emit ProvisionThawFulfilled(_serviceProvider, _verifier, MathUtils.min(thawRequestTokens, tokensRemaining), thawRequestId);
        }
        prov.sharesThawing = sharesThawing;
        prov.tokensThawing = tokensThawing;
        prov.tokens = prov.tokens.sub(_tokens);
    }

    function _addToProvision(address _serviceProvider, address _verifier, uint256 _tokens) internal {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        require(_tokens > 0, "!tokens");
        require(getIdleStake(_serviceProvider) >= _tokens, "insufficient capacity");

        prov.tokens = prov.tokens.add(_tokens);
        serviceProviders[_serviceProvider].tokensProvisioned = serviceProviders[_serviceProvider]
            .tokensProvisioned
            .add(_tokens);
        emit ProvisionIncreased(_serviceProvider, _verifier, _tokens);
    }
}
