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

    uint256 public constant FIXED_POINT_PRECISION = 1e18;

    /// Minimum delegation size
    uint256 public constant MINIMUM_DELEGATION = 1e18;

    constructor(address _subgraphDataServiceAddress)
        L2StakingBackwardsCompatibility(_subgraphDataServiceAddress)
    {}

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

    // can be called by anyone if the indexer has provisioned stake to this verifier
    function stakeToProvision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        require(prov.tokens > 0, "!provision");
        stakeTo(_serviceProvider, _tokens);
        _addToProvision(_serviceProvider, _verifier, _tokens);
    }

    // create a provision
    function provision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) external override notPartialPaused {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(getIdleStake(_serviceProvider) >= _tokens, "insufficient capacity");
        require(verifierAllowlist[_serviceProvider][_verifier], "verifier not allowed");

        _createProvision(_serviceProvider, _tokens, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    // add more tokens from idle stake to an existing provision
    function addToProvision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        _addToProvision(_serviceProvider, _verifier, _tokens);
    }

    // initiate a thawing to remove tokens from a provision
    function thaw(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused returns (bytes32) {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(_tokens > 0, "!tokens");
        Provision storage prov = provisions[_serviceProvider][_verifier];
        ServiceProviderInternal storage serviceProvider = serviceProviders[_serviceProvider];
        bytes32 thawRequestId = keccak256(
            abi.encodePacked(_serviceProvider, _verifier, serviceProvider.nextThawRequestNonce)
        );
        serviceProvider.nextThawRequestNonce += 1;
        ThawRequest storage thawRequest = thawRequests[thawRequestId];

        require(
            getProviderTokensAvailable(_serviceProvider, _verifier) >= _tokens,
            "insufficient tokens available"
        );
        prov.tokensThawing = prov.tokensThawing.add(_tokens);

        thawRequest.shares = prov.sharesThawing.mul(_tokens).div(prov.tokensThawing);
        thawRequest.thawingUntil = uint64(block.timestamp.add(uint256(prov.thawingPeriod)));
        prov.sharesThawing = prov.sharesThawing.add(thawRequest.shares);

        require(prov.nThawRequests < MAX_THAW_REQUESTS, "max thaw requests");
        if (prov.nThawRequests == 0) {
            prov.firstThawRequestId = thawRequestId;
        } else {
            thawRequests[prov.lastThawRequestId].next = thawRequestId;
        }
        prov.lastThawRequestId = thawRequestId;
        prov.nThawRequests += 1;

        emit ProvisionThawInitiated(
            _serviceProvider,
            _verifier,
            _tokens,
            thawRequest.thawingUntil,
            thawRequestId
        );

        return thawRequestId;
    }

    /**
     * @notice Get the amount of service provider's tokens in a provision that have finished thawing
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     */
    function getThawedTokens(address _serviceProvider, address _verifier)
        external
        view
        override
        returns (uint256)
    {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        if (prov.nThawRequests == 0) {
            return 0;
        }
        bytes32 thawRequestId = prov.firstThawRequestId;
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
    function deprovision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused {
        require(isAuthorized(msg.sender, _serviceProvider, _verifier), "!auth");
        require(_tokens > 0, "!tokens");
        ServiceProviderInternal storage serviceProvider = serviceProviders[_serviceProvider];
        _fulfillThawRequests(_serviceProvider, _verifier, _tokens);
        serviceProvider.tokensProvisioned = serviceProvider.tokensProvisioned.sub(_tokens);
    }

    // moves thawed stake from one provision into another provision
    function reprovision(
        address _serviceProvider,
        address _oldVerifier,
        address _newVerifier,
        uint256 _tokens
    ) external override notPartialPaused {
        require(isAuthorized(msg.sender, _serviceProvider, _oldVerifier), "!auth");
        require(isAuthorized(msg.sender, _serviceProvider, _newVerifier), "!auth");
        require(_tokens > 0, "!tokens");

        _fulfillThawRequests(_serviceProvider, _oldVerifier, _tokens);
        _addToProvision(_serviceProvider, _newVerifier, _tokens);
    }

    // moves idle stake back to the owner's account - stake is removed from the protocol
    // global operators are allowed to call this but stake is always sent to the service provider's address
    function unstake(address _serviceProvider, uint256 _tokens) external override notPaused {
        require(isGlobalAuthorized(msg.sender, _serviceProvider), "!auth");
        require(_tokens > 0, "!tokens");
        require(getIdleStake(_serviceProvider) >= _tokens, "insufficient idle stake");

        ServiceProviderInternal storage sp = serviceProviders[_serviceProvider];
        uint256 stakedTokens = sp.tokensStaked;
        // Check that the indexer's stake minus
        // TODO this is only needed until legacy allocations are closed,
        // so we should remove it after the transition period
        require(stakedTokens.sub(_tokens) >= sp.__DEPRECATED_tokensAllocated, "!stake-avail");

        // This is also only during the transition period: we need
        // to ensure tokens stay locked after closing legacy allocations.
        // After sufficient time (56 days?) we should remove the closeAllocation function
        // and set the thawing period to 0.
        uint256 lockingPeriod = __DEPRECATED_thawingPeriod;
        if (lockingPeriod == 0) {
            sp.tokensStaked = stakedTokens.sub(_tokens);
            TokenUtils.pushTokens(graphToken(), _serviceProvider, _tokens);
            emit StakeWithdrawn(_serviceProvider, _tokens);
        } else {
            // Before locking more tokens, withdraw any unlocked ones if possible
            if (
                sp.__DEPRECATED_tokensLockedUntil != 0 &&
                block.number >= sp.__DEPRECATED_tokensLockedUntil
            ) {
                _withdraw(_serviceProvider);
            }
            // TODO remove after the transition period
            // Take into account period averaging for multiple unstake requests
            if (sp.__DEPRECATED_tokensLocked > 0) {
                lockingPeriod = MathUtils.weightedAverageRoundingUp(
                    MathUtils.diffOrZero(sp.__DEPRECATED_tokensLockedUntil, block.number), // Remaining thawing period
                    sp.__DEPRECATED_tokensLocked, // Weighted by remaining unstaked tokens
                    lockingPeriod, // Thawing period
                    _tokens // Weighted by new tokens to unstake
                );
            }

            // Update balances
            sp.__DEPRECATED_tokensLocked = sp.__DEPRECATED_tokensLocked.add(_tokens);
            sp.__DEPRECATED_tokensLockedUntil = block.number.add(lockingPeriod);
            emit StakeLocked(
                _serviceProvider,
                sp.__DEPRECATED_tokensLocked,
                sp.__DEPRECATED_tokensLockedUntil
            );
        }
    }

    // slash a service provider
    // (called by a verifier)
    // if delegation slashing is disabled and it would've happened,
    // this is skipped rather than reverting
    function slash(
        address _serviceProvider,
        uint256 _tokens,
        uint256 _verifierCutAmount,
        address _verifierCutDestination
    ) external override notPartialPaused {
        address verifier = msg.sender;
        Provision storage prov = provisions[_serviceProvider][verifier];
        require(prov.tokens >= _tokens, "insufficient tokens in provision");

        uint256 tokensToSlash = _tokens;

        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        require(
            prov.tokens.mul(prov.maxVerifierCut).div(1e6) >= _verifierCutAmount,
            "verifier cut too high"
        );
        if (_verifierCutAmount > 0) {
            TokenUtils.pushTokens(graphToken(), _verifierCutDestination, _verifierCutAmount);
            emit VerifierCutSent(
                _serviceProvider,
                verifier,
                _verifierCutDestination,
                _verifierCutAmount
            );
        }
        if (providerTokensSlashed > 0) {
            TokenUtils.burnTokens(graphToken(), providerTokensSlashed);
            uint256 provisionFractionSlashed = providerTokensSlashed.mul(FIXED_POINT_PRECISION).div(
                prov.tokens
            );
            // TODO check for rounding issues
            prov.tokensThawing = prov
                .tokensThawing
                .mul(FIXED_POINT_PRECISION - provisionFractionSlashed)
                .div(FIXED_POINT_PRECISION);
            prov.tokens = prov.tokens.sub(providerTokensSlashed);
            serviceProviders[_serviceProvider].tokensProvisioned = serviceProviders[
                _serviceProvider
            ].tokensProvisioned.sub(providerTokensSlashed);
            serviceProviders[_serviceProvider].tokensStaked = serviceProviders[_serviceProvider]
                .tokensStaked
                .sub(providerTokensSlashed);
            emit ProvisionSlashed(_serviceProvider, verifier, providerTokensSlashed);
        }

        tokensToSlash = tokensToSlash.sub(providerTokensSlashed);
        if (tokensToSlash > 0) {
            DelegationPool storage pool;
            if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
                pool = legacyDelegationPools[_serviceProvider];
            } else {
                pool = delegationPools[_serviceProvider][verifier];
            }
            if (delegationSlashingEnabled) {
                require(pool.tokens >= tokensToSlash, "insufficient delegated tokens");
                TokenUtils.burnTokens(graphToken(), tokensToSlash);
                uint256 delegationFractionSlashed = tokensToSlash.mul(FIXED_POINT_PRECISION).div(
                    pool.tokens
                );
                pool.tokens = pool.tokens.sub(tokensToSlash);
                pool.tokensThawing = pool
                    .tokensThawing
                    .mul(FIXED_POINT_PRECISION - delegationFractionSlashed)
                    .div(FIXED_POINT_PRECISION);
                emit DelegationSlashed(_serviceProvider, verifier, tokensToSlash);
            } else {
                emit DelegationSlashingSkipped(_serviceProvider, verifier, tokensToSlash);
            }
        }
    }

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked
    function getStake(address serviceProvider) public view override returns (uint256 tokens) {
        return serviceProviders[serviceProvider].tokensStaked;
    }

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) public view override returns (uint256 tokens) {
        return
            serviceProviders[serviceProvider]
                .tokensStaked
                .sub(serviceProviders[serviceProvider].tokensProvisioned)
                .sub(serviceProviders[serviceProvider].__DEPRECATED_tokensLocked);
    }

    // provisioned tokens from the service provider that are not being thawed
    // `Provision.tokens - Provision.tokensThawing`
    function getProviderTokensAvailable(address _serviceProvider, address _verifier)
        public
        view
        override
        returns (uint256)
    {
        return
            provisions[_serviceProvider][_verifier].tokens.sub(
                provisions[_serviceProvider][_verifier].tokensThawing
            );
    }

    // provisioned tokens from delegators that are not being thawed
    // `Provision.delegatedTokens - Provision.delegatedTokensThawing`
    function getDelegatedTokensAvailable(address _serviceProvider, address _verifier)
        public
        view
        override
        returns (uint256)
    {
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return
                legacyDelegationPools[_serviceProvider].tokens.sub(
                    legacyDelegationPools[_serviceProvider].tokensThawing
                );
        }
        return
            delegationPools[_serviceProvider][_verifier].tokens.sub(
                delegationPools[_serviceProvider][_verifier].tokensThawing
            );
    }

    // provisioned tokens that are not being thawed (including provider tokens and delegation)
    function getTokensAvailable(address _serviceProvider, address _verifier)
        public
        view
        override
        returns (uint256)
    {
        return
            getProviderTokensAvailable(_serviceProvider, _verifier).add(
                getDelegatedTokensAvailable(_serviceProvider, _verifier)
            );
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

    function getProvision(address _serviceProvider, address _verifier)
        public
        view
        override
        returns (Provision memory)
    {
        return provisions[_serviceProvider][_verifier];
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param _operator Address to authorize or unauthorize
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(
        address _operator,
        address _verifier,
        bool _allowed
    ) external override {
        require(_operator != msg.sender, "operator == sender");
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
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
    function setGlobalOperator(address _operator, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        globalOperatorAuth[msg.sender][_operator] = _allowed;
        emit GlobalOperatorSet(msg.sender, _operator, _allowed);
    }

    /**
     * @notice Check if an operator is authorized for the caller on all their allowlisted verifiers and global stake.
     * @param _operator The address to check for auth
     * @param _serviceProvider The service provider on behalf of whom they're claiming to act
     */
    function isGlobalAuthorized(address _operator, address _serviceProvider)
        public
        view
        override
        returns (bool)
    {
        return _operator == _serviceProvider || globalOperatorAuth[_serviceProvider][_operator];
    }

    /**
     * @notice Withdraw indexer tokens once the thawing period has passed.
     * @dev This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will also withdraw.
     */
    function withdrawLocked(address _serviceProvider) external override notPaused {
        require(isGlobalAuthorized(msg.sender, _serviceProvider), "!auth");
        _withdraw(_serviceProvider);
    }

    function delegate(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) public override notPartialPaused {
        // Transfer tokens to stake from caller to this contract
        TokenUtils.pullTokens(graphToken(), msg.sender, _tokens);
        _delegate(_serviceProvider, _verifier, _tokens);
    }

    // For backwards compatibility, delegates to the subgraph data service
    function delegate(address _serviceProvider, uint256 _tokens) external {
        delegate(_serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, _tokens);
    }

    // For backwards compatibility, undelegates from the subgraph data service
    function undelegate(address _serviceProvider, uint256 _shares) external {
        undelegate(_serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, _shares);
    }

    // For backwards compatibility, withdraws delegated tokens from the subgraph data service
    function withdrawDelegated(address _serviceProvider, address _newServiceProvider) external {
        withdrawDelegated(_serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, _newServiceProvider);
    }

    function _delegate(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) internal {
        require(_tokens > 0, "!tokens");
        require(provisions[_serviceProvider][_verifier].tokens >= 0, "!provision");

        // Only allow delegations over a minimum, to prevent rounding attacks
        require(_tokens >= MINIMUM_DELEGATION, "!minimum-delegation");
        DelegationPool storage pool;
        Delegation storage delegation = pool.delegators[msg.sender];
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            pool = legacyDelegationPools[_serviceProvider];
        } else {
            pool = delegationPools[_serviceProvider][_verifier];
        }

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0)
            ? _tokens
            : _tokens.mul(pool.shares).div(pool.tokens.sub(pool.tokensThawing));
        require(shares > 0, "!shares");

        pool.tokens = pool.tokens.add(_tokens);
        pool.shares = pool.shares.add(shares);

        delegation.shares = delegation.shares.add(shares);

        emit TokensDelegated(_serviceProvider, _verifier, msg.sender, _tokens);
    }

    // undelegete tokens from a service provider
    // the shares are burned and replaced with shares in the thawing pool
    function undelegate(
        address _serviceProvider,
        address _verifier,
        uint256 _shares
    ) public override notPartialPaused {
        require(_shares > 0, "!shares");
        DelegationPool storage pool;
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            pool = legacyDelegationPools[_serviceProvider];
        } else {
            pool = delegationPools[_serviceProvider][_verifier];
        }
        Delegation storage delegation = pool.delegators[msg.sender];
        require(delegation.shares >= _shares, "!shares-avail");

        uint256 tokens = _shares.mul(pool.tokens.sub(pool.tokensThawing)).div(pool.shares);

        uint256 thawingShares = pool.tokensThawing == 0
            ? tokens
            : tokens.mul(pool.sharesThawing).div(pool.tokensThawing);
        pool.tokensThawing = pool.tokensThawing.add(tokens);

        pool.shares = pool.shares.sub(_shares);
        delegation.shares = delegation.shares.sub(_shares);

        bytes32 thawRequestId = keccak256(
            abi.encodePacked(
                _serviceProvider,
                _verifier,
                msg.sender,
                delegation.nextThawRequestNonce
            )
        );
        delegation.nextThawRequestNonce += 1;
        ThawRequest storage thawRequest = thawRequests[thawRequestId];
        thawRequest.shares = thawingShares;
        thawRequest.thawingUntil = uint64(
            block.timestamp.add(uint256(provisions[_serviceProvider][_verifier].thawingPeriod))
        );
        require(delegation.nThawRequests < MAX_THAW_REQUESTS, "max thaw requests");
        if (delegation.nThawRequests == 0) {
            delegation.firstThawRequestId = thawRequestId;
        } else {
            thawRequests[delegation.lastThawRequestId].next = thawRequestId;
        }
        delegation.lastThawRequestId = thawRequestId;
        delegation.nThawRequests += 1;

        emit TokensUndelegated(_serviceProvider, _verifier, msg.sender, tokens);
    }

    function withdrawDelegated(
        address _serviceProvider,
        address _verifier,
        address _newServiceProvider
    ) public override notPartialPaused {
        DelegationPool storage pool;
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            pool = legacyDelegationPools[_serviceProvider];
        } else {
            pool = delegationPools[_serviceProvider][_verifier];
        }
        Delegation storage delegation = pool.delegators[msg.sender];
        uint256 thawedTokens = 0;

        uint256 sharesThawing = pool.sharesThawing;
        uint256 tokensThawing = pool.tokensThawing;
        require(delegation.nThawRequests > 0, "no thaw requests");
        bytes32 thawRequestId = delegation.firstThawRequestId;
        while (thawRequestId != bytes32(0)) {
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            if (thawRequest.thawingUntil <= block.timestamp) {
                uint256 tokens = thawRequest.shares.mul(tokensThawing).div(sharesThawing);
                tokensThawing = tokensThawing.sub(tokens);
                sharesThawing = sharesThawing.sub(thawRequest.shares);
                thawedTokens = thawedTokens.add(tokens);
                delete thawRequests[thawRequestId];
                delegation.firstThawRequestId = thawRequest.next;
                delegation.nThawRequests -= 1;
                if (delegation.nThawRequests == 0) {
                    delegation.lastThawRequestId = bytes32(0);
                }
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }

        pool.tokens = pool.tokens.sub(thawedTokens);
        pool.sharesThawing = sharesThawing;
        pool.tokensThawing = tokensThawing;

        if (_newServiceProvider != address(0)) {
            _delegate(_newServiceProvider, _verifier, thawedTokens);
        } else {
            TokenUtils.pushTokens(graphToken(), msg.sender, thawedTokens);
        }
        emit DelegatedTokensWithdrawn(_serviceProvider, _verifier, msg.sender, thawedTokens);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     * @param _indexer Address of indexer to withdraw funds from
     */
    function _withdraw(address _indexer) private {
        // Get tokens available for withdraw and update balance
        ServiceProviderInternal storage sp = serviceProviders[_indexer];
        uint256 tokensToWithdraw = sp.__DEPRECATED_tokensLocked;
        require(tokensToWithdraw > 0, "!tokens");
        require(block.number >= sp.__DEPRECATED_tokensLockedUntil, "locked");

        // Reset locked tokens
        sp.__DEPRECATED_tokensLocked = 0;
        sp.__DEPRECATED_tokensLockedUntil = 0;

        sp.tokensStaked = sp.tokensStaked.sub(tokensToWithdraw);

        // Return tokens to the indexer
        TokenUtils.pushTokens(graphToken(), _indexer, tokensToWithdraw);

        emit StakeWithdrawn(_indexer, tokensToWithdraw);
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
    ) internal {
        require(_tokens >= MIN_PROVISION_SIZE, "!tokens");
        require(_maxVerifierCut <= MAX_MAX_VERIFIER_CUT, "maxVerifierCut too high");
        require(_thawingPeriod <= maxThawingPeriod, "thawingPeriod too high");
        provisions[_serviceProvider][_verifier] = Provision({
            tokens: _tokens,
            tokensThawing: 0,
            sharesThawing: 0,
            maxVerifierCut: _maxVerifierCut,
            thawingPeriod: _thawingPeriod,
            firstThawRequestId: bytes32(0),
            lastThawRequestId: bytes32(0),
            nThawRequests: 0
        });

        ServiceProviderInternal storage sp = serviceProviders[_serviceProvider];
        sp.tokensProvisioned = sp.tokensProvisioned.add(_tokens);

        emit ProvisionCreated(
            _serviceProvider,
            _verifier,
            _tokens,
            _maxVerifierCut,
            _thawingPeriod
        );
    }

    function _fulfillThawRequests(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) internal {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        uint256 tokensRemaining = _tokens;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;
        while (tokensRemaining > 0) {
            require(prov.nThawRequests > 0, "not enough thawed tokens");
            bytes32 thawRequestId = prov.firstThawRequestId;
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            require(thawRequest.thawingUntil <= block.timestamp, "thawing period not over");
            uint256 thawRequestTokens = thawRequest.shares.mul(tokensThawing).div(sharesThawing);
            if (thawRequestTokens <= tokensRemaining) {
                tokensRemaining = tokensRemaining.sub(thawRequestTokens);
                delete thawRequests[thawRequestId];
                prov.firstThawRequestId = thawRequest.next;
                prov.nThawRequests -= 1;
                tokensThawing = tokensThawing.sub(thawRequestTokens);
                sharesThawing = sharesThawing.sub(thawRequest.shares);
                if (prov.nThawRequests == 0) {
                    prov.lastThawRequestId = bytes32(0);
                }
            } else {
                // TODO check for potential rounding issues
                uint256 sharesRemoved = tokensRemaining.mul(prov.sharesThawing).div(
                    prov.tokensThawing
                );
                thawRequest.shares = thawRequest.shares.sub(sharesRemoved);
                tokensThawing = tokensThawing.sub(tokensRemaining);
                sharesThawing = sharesThawing.sub(sharesRemoved);
            }
            emit ProvisionThawFulfilled(
                _serviceProvider,
                _verifier,
                MathUtils.min(thawRequestTokens, tokensRemaining),
                thawRequestId
            );
        }
        prov.sharesThawing = sharesThawing;
        prov.tokensThawing = tokensThawing;
        prov.tokens = prov.tokens.sub(_tokens);
    }

    function _addToProvision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) internal {
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
