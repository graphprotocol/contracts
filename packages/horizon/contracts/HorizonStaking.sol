// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";

import { IHorizonStakingBase } from "./IHorizonStakingBase.sol";
import { TokenUtils } from "./utils/TokenUtils.sol";
import { MathUtils } from "./utils/MathUtils.sol";
import { Managed } from "./Managed.sol";
import { IGraphToken } from "./IGraphToken.sol";
import { HorizonStakingV1Storage } from "./HorizonStakingStorage.sol";

/**
 * @title HorizonStaking contract
 * @dev This contract is the main Staking contract in The Graph protocol after Horizon.
 * It is designed to be deployed as an upgrade to the L2Staking contract from the legacy contracts
 * package.
 * It uses an HorizonStakingExtension contract to implement the full IHorizonStaking interface through delegatecalls.
 * This is due to the contract size limit on Arbitrum (24kB like mainnet).
 */
contract HorizonStaking is HorizonStakingV1Storage, IHorizonStakingBase, GraphUpgradeable {
    /// @dev 100% in parts per million
    uint32 internal constant MAX_PPM = 1000000;

    /// Maximum value that can be set as the maxVerifierCut in a provision.
    /// It is equivalent to 100% in parts-per-million
    uint32 private constant MAX_MAX_VERIFIER_CUT = 1000000; // 100%

    /// Minimum size of a provision
    uint256 private constant MIN_PROVISION_SIZE = 1e18;

    /// Maximum number of simultaneous stake thaw requests or undelegations
    uint256 private constant MAX_THAW_REQUESTS = 100;

    uint256 private constant FIXED_POINT_PRECISION = 1e18;

    /// Minimum delegation size
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    address private immutable STAKING_EXTENSION_ADDRESS;
    address private immutable SUBGRAPH_DATA_SERVICE_ADDRESS;

    error HorizonStakingInvalidVerifier(address verifier);
    error HorizonStakingVerifierAlreadyAllowed(address verifier);
    error HorizonStakingVerifierNotAllowed(address verifier);
    error HorizonStakingInvalidZeroTokens();
    error HorizonStakingInvalidProvision(address serviceProvider, address verifier);
    error HorizonStakingNotAuthorized(address caller, address serviceProvider, address verifier);
    error HorizonStakingInsufficientCapacity();
    error HorizonStakingInsufficientShares();
    error HorizonStakingInsufficientCapacityForLegacyAllocations();
    error HorizonStakingTooManyThawRequests();
    error HorizonStakingInsufficientTokens(uint256 expected, uint256 available);

    modifier onlyAuthorized(address _serviceProvider, address _verifier) {
        if (!isAuthorized(msg.sender, _serviceProvider, _verifier)) {
            revert HorizonStakingNotAuthorized(msg.sender, _serviceProvider, _verifier);
        }
        _;
    }

    constructor(
        address _controller,
        address _stakingExtensionAddress,
        address _subgraphDataServiceAddress
    ) Managed(_controller) {
        STAKING_EXTENSION_ADDRESS = _stakingExtensionAddress;
        SUBGRAPH_DATA_SERVICE_ADDRESS = _subgraphDataServiceAddress;
    }

    /**
     * @notice Delegates the current call to the StakingExtension implementation.
     * @dev This function does not return to its internal call site, it will return directly to the
     * external caller.
     */
    // solhint-disable-next-line payable-fallback, no-complex-fallback
    fallback() external {
        //require(_implementation() != address(0), "only through proxy");
        address extensionImpl = STAKING_EXTENSION_ADDRESS;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // (a) get free memory pointer
            let ptr := mload(0x40)

            // (1) copy incoming call data
            calldatacopy(ptr, 0, calldatasize())

            // (2) forward call to logic contract
            let result := delegatecall(gas(), extensionImpl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()

            // (3) retrieve return data
            returndatacopy(ptr, 0, size)

            // (4) forward return data back to caller
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
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
        if (_tokens == 0) {
            revert HorizonStakingInvalidZeroTokens();
        }

        // Transfer tokens to stake from caller to this contract
        TokenUtils.pullTokens(_graphToken(), msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_serviceProvider, _tokens);
    }

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider, provisioned
     * to a specific verifier. The provider must have previously provisioned stake to that verifier.
     * @param _serviceProvider Address of the indexer
     * @param _verifier Address of the verifier
     * @param _tokens Amount of tokens to stake
     */
    function stakeToProvision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused {
        stakeTo(_serviceProvider, _tokens);
        _addToProvision(_serviceProvider, _verifier, _tokens);
    }

    /**
     * @notice Provision stake to a verifier. The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param _tokens The amount of tokens that will be locked and slashable
     * @param _maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param _thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function provision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) external override notPartialPaused onlyAuthorized(_serviceProvider, _verifier) {
        if (getIdleStake(_serviceProvider) < _tokens) {
            revert HorizonStakingInsufficientCapacity();
        }

        _createProvision(_serviceProvider, _tokens, _verifier, _maxVerifierCut, _thawingPeriod);
    }

    /**
     * @notice Add more tokens to an existing provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     * @param _tokens The amount of tokens to add to the provision
     */
    function addToProvision(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused onlyAuthorized(_serviceProvider, _verifier) {
        _addToProvision(_serviceProvider, _verifier, _tokens);
    }

    /**
     * @notice Start thawing tokens to remove them from a provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     * @param _tokens The amount of tokens to thaw
     */
    function thaw(
        address _serviceProvider,
        address _verifier,
        uint256 _tokens
    ) external override notPartialPaused onlyAuthorized(_serviceProvider, _verifier) returns (bytes32) {
        if (_tokens == 0) {
            revert HorizonStakingInvalidZeroTokens();
        }
        Provision storage prov = provisions[_serviceProvider][_verifier];
        ServiceProviderInternal storage serviceProvider = serviceProviders[_serviceProvider];
        bytes32 thawRequestId = keccak256(
            abi.encodePacked(_serviceProvider, _verifier, serviceProvider.nextThawRequestNonce)
        );
        serviceProvider.nextThawRequestNonce += 1;
        ThawRequest storage thawRequest = thawRequests[thawRequestId];

        require(getProviderTokensAvailable(_serviceProvider, _verifier) >= _tokens, "insufficient tokens available");
        prov.tokensThawing = prov.tokensThawing + _tokens;

        if (prov.sharesThawing == 0) {
            thawRequest.shares = _tokens;
        } else {
            thawRequest.shares = (prov.sharesThawing * _tokens) / prov.tokensThawing;
        }

        thawRequest.thawingUntil = uint64(block.timestamp + uint256(prov.thawingPeriod));
        prov.sharesThawing = prov.sharesThawing + thawRequest.shares;

        if (prov.nThawRequests >= MAX_THAW_REQUESTS) {
            revert HorizonStakingTooManyThawRequests();
        }
        if (prov.nThawRequests == 0) {
            prov.firstThawRequestId = thawRequestId;
        } else {
            thawRequests[prov.lastThawRequestId].next = thawRequestId;
        }
        prov.lastThawRequestId = thawRequestId;
        prov.nThawRequests += 1;

        emit ProvisionThawInitiated(_serviceProvider, _verifier, _tokens, thawRequest.thawingUntil, thawRequestId);

        return thawRequestId;
    }

    /**
     * @notice Get the amount of service provider's tokens in a provision that have finished thawing
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     */
    function getThawedTokens(address _serviceProvider, address _verifier) external view returns (uint256) {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        if (prov.nThawRequests == 0) {
            return 0;
        }
        bytes32 thawRequestId = prov.firstThawRequestId;
        uint256 tokens = 0;
        while (thawRequestId != bytes32(0)) {
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            if (thawRequest.thawingUntil <= block.timestamp) {
                tokens += (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
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
        if (_tokens == 0) {
            revert HorizonStakingInvalidZeroTokens();
        }
        _fulfillThawRequests(_serviceProvider, _verifier, _tokens);
    }

    /**
     * @notice Move already thawed stake from one provision into another provision
     * This function can be called by the service provider or by an operator authorized by the provider
     * for the two corresponding verifiers.
     * The provider must have previously provisioned tokens to the new verifier.
     * @param _serviceProvider The service provider address
     * @param _oldVerifier The verifier address for which the tokens are currently provisioned
     * @param _newVerifier The verifier address for which the tokens will be provisioned
     * @param _tokens The amount of tokens to move
     */
    function reprovision(
        address _serviceProvider,
        address _oldVerifier,
        address _newVerifier,
        uint256 _tokens
    )
        external
        override
        notPartialPaused
        onlyAuthorized(_serviceProvider, _oldVerifier)
        onlyAuthorized(_serviceProvider, _newVerifier)
    {
        _fulfillThawRequests(_serviceProvider, _oldVerifier, _tokens);
        _addToProvision(_serviceProvider, _newVerifier, _tokens);
    }

    /**
     * @notice Move idle stake back to the owner's account.
     * If tokens were thawing they must be deprovisioned first.
     * Stake is removed from the protocol.
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external override notPaused {
        address serviceProvider = msg.sender;
        if (_tokens == 0) {
            revert HorizonStakingInvalidZeroTokens();
        }
        if (getIdleStake(serviceProvider) < _tokens) {
            revert HorizonStakingInsufficientCapacity();
        }

        ServiceProviderInternal storage sp = serviceProviders[serviceProvider];
        uint256 stakedTokens = sp.tokensStaked;
        // Check that the indexer's stake minus the tokens to unstake is sufficient
        // to cover existing allocations
        // TODO this is only needed until legacy allocations are closed,
        // so we should remove it after the transition period
        if ((stakedTokens - _tokens) < sp.__DEPRECATED_tokensAllocated) {
            revert HorizonStakingInsufficientCapacityForLegacyAllocations();
        }

        // This is also only during the transition period: we need
        // to ensure tokens stay locked after closing legacy allocations.
        // After sufficient time (56 days?) we should remove the closeAllocation function
        // and set the thawing period to 0.
        uint256 lockingPeriod = __DEPRECATED_thawingPeriod;
        if (lockingPeriod == 0) {
            sp.tokensStaked = stakedTokens - _tokens;
            TokenUtils.pushTokens(_graphToken(), serviceProvider, _tokens);
            emit StakeWithdrawn(serviceProvider, _tokens);
        } else {
            // Before locking more tokens, withdraw any unlocked ones if possible
            if (sp.__DEPRECATED_tokensLockedUntil != 0 && block.number >= sp.__DEPRECATED_tokensLockedUntil) {
                _withdraw(serviceProvider);
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
            sp.__DEPRECATED_tokensLocked = sp.__DEPRECATED_tokensLocked + _tokens;
            sp.__DEPRECATED_tokensLockedUntil = block.number + lockingPeriod;
            emit StakeLocked(serviceProvider, sp.__DEPRECATED_tokensLocked, sp.__DEPRECATED_tokensLockedUntil);
        }
    }

    /**
     * @notice Slash a service provider. This can only be called by a verifier to which
     * the provider has provisioned stake, and up to the amount of tokens they have provisioned.
     * @dev If delegation slashing is disabled, and the amount of tokens is more than the
     * provider's provisioned self-stake, the delegation slashing is skipped without reverting.
     * @param _serviceProvider The service provider to slash
     * @param _tokens The amount of tokens to slash
     * @param _verifierCutAmount The amount of tokens to transfer instead of burning
     * @param _verifierCutDestination The address to transfer the verifier cut to
     */
    function slash(
        address _serviceProvider,
        uint256 _tokens,
        uint256 _verifierCutAmount,
        address _verifierCutDestination
    ) external override notPartialPaused {
        address verifier = msg.sender;
        Provision storage prov = provisions[_serviceProvider][verifier];
        if (prov.tokens < _tokens) {
            revert HorizonStakingInsufficientTokens(_tokens, prov.tokens);
        }

        uint256 tokensToSlash = _tokens;

        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        require((prov.tokens * prov.maxVerifierCut) / MAX_PPM >= _verifierCutAmount, "verifier cut too high");
        if (_verifierCutAmount > 0) {
            TokenUtils.pushTokens(_graphToken(), _verifierCutDestination, _verifierCutAmount);
            emit VerifierCutSent(_serviceProvider, verifier, _verifierCutDestination, _verifierCutAmount);
        }
        if (providerTokensSlashed > 0) {
            TokenUtils.burnTokens(_graphToken(), providerTokensSlashed);
            uint256 provisionFractionSlashed = (providerTokensSlashed * FIXED_POINT_PRECISION) / prov.tokens;
            // TODO check for rounding issues
            prov.tokensThawing =
                (prov.tokensThawing * (FIXED_POINT_PRECISION - provisionFractionSlashed)) /
                (FIXED_POINT_PRECISION);
            prov.tokens = prov.tokens - providerTokensSlashed;
            serviceProviders[_serviceProvider].tokensProvisioned =
                serviceProviders[_serviceProvider].tokensProvisioned -
                providerTokensSlashed;
            serviceProviders[_serviceProvider].tokensStaked =
                serviceProviders[_serviceProvider].tokensStaked -
                providerTokensSlashed;
            emit ProvisionSlashed(_serviceProvider, verifier, providerTokensSlashed);
        }

        tokensToSlash = tokensToSlash - providerTokensSlashed;
        if (tokensToSlash > 0) {
            DelegationPoolInternal storage pool;
            if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
                pool = legacyDelegationPools[_serviceProvider];
            } else {
                pool = delegationPools[_serviceProvider][verifier];
            }
            if (delegationSlashingEnabled) {
                require(pool.tokens >= tokensToSlash, "insufficient delegated tokens");
                TokenUtils.burnTokens(_graphToken(), tokensToSlash);
                uint256 delegationFractionSlashed = (tokensToSlash * FIXED_POINT_PRECISION) / pool.tokens;
                pool.tokens = pool.tokens - tokensToSlash;
                pool.tokensThawing =
                    (pool.tokensThawing * (FIXED_POINT_PRECISION - delegationFractionSlashed)) /
                    FIXED_POINT_PRECISION;
                emit DelegationSlashed(_serviceProvider, verifier, tokensToSlash);
            } else {
                emit DelegationSlashingSkipped(_serviceProvider, verifier, tokensToSlash);
            }
        }
    }

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @param _operator The address to check for auth
     * @param _serviceProvider The service provider on behalf of whom they're claiming to act
     * @param _verifier The verifier / data service on which they're claiming to act
     */
    function isAuthorized(
        address _operator,
        address _serviceProvider,
        address _verifier
    ) public view override returns (bool) {
        if (_operator == _serviceProvider) {
            return true;
        }
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return legacyOperatorAuth[_serviceProvider][_operator];
        } else {
            return operatorAuth[_serviceProvider][_verifier][_operator];
        }
    }

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) public view override returns (uint256 tokens) {
        return
            serviceProviders[serviceProvider].tokensStaked -
            serviceProviders[serviceProvider].tokensProvisioned -
            serviceProviders[serviceProvider].__DEPRECATED_tokensLocked;
    }

    // provisioned tokens from the service provider that are not being thawed
    // `Provision.tokens - Provision.tokensThawing`
    function getProviderTokensAvailable(
        address _serviceProvider,
        address _verifier
    ) public view override returns (uint256) {
        return provisions[_serviceProvider][_verifier].tokens - provisions[_serviceProvider][_verifier].tokensThawing;
    }

    /**
     * @notice Withdraw indexer tokens once the thawing period has passed.
     * @dev This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will also withdraw.
     */
    function withdrawLocked() external override notPaused {
        _withdraw(msg.sender);
    }

    function delegate(address _serviceProvider, address _verifier, uint256 _tokens) public override notPartialPaused {
        // Transfer tokens to stake from caller to this contract
        TokenUtils.pullTokens(_graphToken(), msg.sender, _tokens);
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

    function _delegate(address _serviceProvider, address _verifier, uint256 _tokens) internal {
        require(_tokens > 0, "!tokens");
        require(provisions[_serviceProvider][_verifier].tokens >= 0, "!provision");

        // Only allow delegations over a minimum, to prevent rounding attacks
        require(_tokens >= MINIMUM_DELEGATION, "!minimum-delegation");
        DelegationPoolInternal storage pool;
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            pool = legacyDelegationPools[_serviceProvider];
        } else {
            pool = delegationPools[_serviceProvider][_verifier];
        }
        Delegation storage delegation = pool.delegators[msg.sender];

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? _tokens : ((_tokens * pool.shares) / (pool.tokens - pool.tokensThawing));
        require(shares > 0, "!shares");

        pool.tokens = pool.tokens + _tokens;
        pool.shares = pool.shares + shares;

        delegation.shares = delegation.shares + shares;

        emit TokensDelegated(_serviceProvider, _verifier, msg.sender, _tokens);
    }

    // undelegate tokens from a service provider
    // the shares are burned and replaced with shares in the thawing pool
    function undelegate(address _serviceProvider, address _verifier, uint256 _shares) public override notPartialPaused {
        require(_shares > 0, "!shares");
        DelegationPoolInternal storage pool;
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            pool = legacyDelegationPools[_serviceProvider];
        } else {
            pool = delegationPools[_serviceProvider][_verifier];
        }
        Delegation storage delegation = pool.delegators[msg.sender];
        require(delegation.shares >= _shares, "!shares-avail");

        uint256 tokens = (_shares * (pool.tokens - pool.tokensThawing)) / pool.shares;

        uint256 thawingShares = pool.tokensThawing == 0 ? tokens : ((tokens * pool.sharesThawing) / pool.tokensThawing);
        pool.tokensThawing = pool.tokensThawing + tokens;

        pool.shares = pool.shares - _shares;
        delegation.shares = delegation.shares - _shares;
        if (delegation.shares != 0) {
            uint256 remainingTokens = (delegation.shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
            require(remainingTokens >= MINIMUM_DELEGATION, "!minimum-delegation");
        }
        bytes32 thawRequestId = keccak256(
            abi.encodePacked(_serviceProvider, _verifier, msg.sender, delegation.nextThawRequestNonce)
        );
        delegation.nextThawRequestNonce += 1;
        ThawRequest storage thawRequest = thawRequests[thawRequestId];
        thawRequest.shares = thawingShares;
        thawRequest.thawingUntil = uint64(
            block.timestamp + uint256(provisions[_serviceProvider][_verifier].thawingPeriod)
        );
        require(delegation.nThawRequests < MAX_THAW_REQUESTS, "max thaw requests");
        if (delegation.nThawRequests == 0) {
            delegation.firstThawRequestId = thawRequestId;
        } else {
            thawRequests[delegation.lastThawRequestId].next = thawRequestId;
        }
        delegation.lastThawRequestId = thawRequestId;
        unchecked {
            delegation.nThawRequests += 1;
        }
        emit TokensUndelegated(_serviceProvider, _verifier, msg.sender, tokens);
    }

    function withdrawDelegated(
        address _serviceProvider,
        address _verifier,
        address _newServiceProvider
    ) public override notPartialPaused {
        DelegationPoolInternal storage pool;
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
                uint256 tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
                tokensThawing = tokensThawing - tokens;
                sharesThawing = sharesThawing - thawRequest.shares;
                thawedTokens = thawedTokens + tokens;
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

        pool.tokens = pool.tokens - thawedTokens;
        pool.sharesThawing = sharesThawing;
        pool.tokensThawing = tokensThawing;

        if (_newServiceProvider != address(0)) {
            _delegate(_newServiceProvider, _verifier, thawedTokens);
        } else {
            TokenUtils.pushTokens(_graphToken(), msg.sender, thawedTokens);
        }
        emit DelegatedTokensWithdrawn(_serviceProvider, _verifier, msg.sender, thawedTokens);
    }

    function setDelegationSlashingEnabled(bool _enabled) external override onlyGovernor {
        delegationSlashingEnabled = _enabled;
        emit DelegationSlashingEnabled(_enabled);
    }

    // To be called at the end of the transition period, to set the deprecated thawing period to 0
    function clearThawingPeriod() external onlyGovernor {
        __DEPRECATED_thawingPeriod = 0;
        emit ParameterUpdated("thawingPeriod");
    }

    function setMaxThawingPeriod(uint64 _maxThawingPeriod) external override onlyGovernor {
        maxThawingPeriod = _maxThawingPeriod;
        emit ParameterUpdated("maxThawingPeriod");
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

        sp.tokensStaked = sp.tokensStaked - tokensToWithdraw;

        // Return tokens to the indexer
        TokenUtils.pushTokens(_graphToken(), _indexer, tokensToWithdraw);

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
            createdAt: uint64(block.timestamp),
            firstThawRequestId: bytes32(0),
            lastThawRequestId: bytes32(0),
            nThawRequests: 0
        });

        ServiceProviderInternal storage sp = serviceProviders[_serviceProvider];
        sp.tokensProvisioned = sp.tokensProvisioned + _tokens;

        emit ProvisionCreated(_serviceProvider, _verifier, _tokens, _maxVerifierCut, _thawingPeriod);
    }

    function _fulfillThawRequests(address _serviceProvider, address _verifier, uint256 _tokens) internal {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        uint256 tokensRemaining = _tokens;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;
        while (tokensRemaining > 0) {
            require(prov.nThawRequests > 0, "not enough thawed tokens");
            bytes32 thawRequestId = prov.firstThawRequestId;
            ThawRequest storage thawRequest = thawRequests[thawRequestId];
            require(thawRequest.thawingUntil <= block.timestamp, "thawing period not over");
            uint256 thawRequestTokens = (thawRequest.shares * tokensThawing) / sharesThawing;
            if (thawRequestTokens <= tokensRemaining) {
                tokensRemaining = tokensRemaining - thawRequestTokens;
                delete thawRequests[thawRequestId];
                prov.firstThawRequestId = thawRequest.next;
                prov.nThawRequests -= 1;
                tokensThawing = tokensThawing - thawRequestTokens;
                sharesThawing = sharesThawing - thawRequest.shares;
                if (prov.nThawRequests == 0) {
                    prov.lastThawRequestId = bytes32(0);
                }
            } else {
                // TODO check for potential rounding issues
                uint256 sharesRemoved = (tokensRemaining * prov.sharesThawing) / prov.tokensThawing;
                thawRequest.shares = thawRequest.shares - sharesRemoved;
                tokensThawing = tokensThawing - tokensRemaining;
                sharesThawing = sharesThawing - sharesRemoved;
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
        prov.tokens = prov.tokens - _tokens;
        serviceProviders[_serviceProvider].tokensProvisioned -= _tokens;
    }

    function _addToProvision(address _serviceProvider, address _verifier, uint256 _tokens) internal {
        Provision storage prov = provisions[_serviceProvider][_verifier];
        if (_tokens == 0) {
            revert HorizonStakingInvalidZeroTokens();
        }
        if (prov.createdAt == 0) {
            revert HorizonStakingInvalidProvision(_serviceProvider, _verifier);
        }
        if (getIdleStake(_serviceProvider) < _tokens) {
            revert HorizonStakingInsufficientCapacity();
        }

        prov.tokens = prov.tokens + _tokens;
        serviceProviders[_serviceProvider].tokensProvisioned =
            serviceProviders[_serviceProvider].tokensProvisioned +
            _tokens;
        emit ProvisionIncreased(_serviceProvider, _verifier, _tokens);
    }

    /**
     * @dev Stake tokens on the service provider.
     * TODO: Move to HorizonStaking after the transition period
     * @param _serviceProvider Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _serviceProvider, uint256 _tokens) internal {
        // Deposit tokens into the indexer stake
        serviceProviders[_serviceProvider].tokensStaked = serviceProviders[_serviceProvider].tokensStaked + _tokens;

        emit StakeDeposited(_serviceProvider, _tokens);
    }

    function _graphToken() internal view returns (IGraphToken) {
        return IGraphToken(GRAPH_TOKEN);
    }
}
