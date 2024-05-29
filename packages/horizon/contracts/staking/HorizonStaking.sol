// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStakingMain } from "../interfaces/internal/IHorizonStakingMain.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { MathUtils } from "../libraries/MathUtils.sol";
import { PPMMath } from "../libraries/PPMMath.sol";
import { LinkedList } from "../libraries/LinkedList.sol";

import { HorizonStakingBase } from "./HorizonStakingBase.sol";

/**
 * @title HorizonStaking contract
 * @dev This contract is the main Staking contract in The Graph protocol after the Horizon upgrade.
 * It is designed to be deployed as an upgrade to the L2Staking contract from the legacy contracts
 * package.
 * @dev It uses a HorizonStakingExtension contract to implement the full IHorizonStaking interface through delegatecalls.
 * This is due to the contract size limit on Arbitrum (24kB). The extension contract contains functionality to support
 * the legacy staking functions and the transfer tools. Both can be eventually safely removed without affecting
 * the main staking contract.
 */
contract HorizonStaking is HorizonStakingBase, IHorizonStakingMain {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;
    using LinkedList for LinkedList.List;

    /// @dev Maximum value that can be set as the maxVerifierCut in a provision.
    /// It is equivalent to 100% in parts-per-million
    uint32 private constant MAX_MAX_VERIFIER_CUT = uint32(PPMMath.MAX_PPM);

    /// @dev Minimum size of a provision
    uint256 private constant MIN_PROVISION_SIZE = 1e18;

    /// @dev Fixed point precision
    uint256 private constant FIXED_POINT_PRECISION = 1e18;

    /// @dev Maximum number of simultaneous stake thaw requests (per provision) or undelegations (per delegation)
    uint256 private constant MAX_THAW_REQUESTS = 100;

    /// @dev Minimum amount of delegation to prevent rounding attacks.
    /// TODO: remove this after L2 transfer tool for delegation is removed
    /// (delegation on L2 has its own slippage protection)
    uint256 private constant MIN_DELEGATION = 1e18;

    address private immutable STAKING_EXTENSION_ADDRESS;

    modifier onlyAuthorized(address serviceProvider, address verifier) {
        require(
            _isAuthorized(msg.sender, serviceProvider, verifier),
            HorizonStakingNotAuthorized(msg.sender, serviceProvider, verifier)
        );
        _;
    }

    constructor(
        address controller,
        address stakingExtensionAddress,
        address subgraphDataServiceAddress
    ) HorizonStakingBase(controller, subgraphDataServiceAddress) {
        STAKING_EXTENSION_ADDRESS = stakingExtensionAddress;
    }

    /**
     * @notice Delegates the current call to the StakingExtension implementation.
     * @dev This function does not return to its internal call site, it will return directly to the
     * external caller.
     */
    // solhint-disable-next-line payable-fallback, no-complex-fallback
    fallback() external {
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

    /*
     * STAKING
     */

    /**
     * @notice Deposit tokens on the caller's stake.
     * @param tokens Amount of tokens to stake
     */
    function stake(uint256 tokens) external override notPaused {
        _stakeTo(msg.sender, tokens);
    }

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider.
     * @param serviceProvider Address of the service provider
     * @param tokens Amount of tokens to stake
     */
    function stakeTo(address serviceProvider, uint256 tokens) external override notPaused {
        _stakeTo(serviceProvider, tokens);
    }

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider, provisioned
     * to a specific verifier. The provider must have previously provisioned stake to that verifier.
     * @param serviceProvider Address of the service provider
     * @param verifier Address of the verifier
     * @param tokens Amount of tokens to stake
     */
    function stakeToProvision(address serviceProvider, address verifier, uint256 tokens) external override notPaused {
        _stakeTo(serviceProvider, tokens);
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /**
     * @notice Move idle stake back to the owner's account.
     * If tokens were thawing they must be deprovisioned first.
     * Stake is removed from the protocol.
     * @param tokens Amount of tokens to unstake
     */
    function unstake(uint256 tokens) external override notPaused {
        _unstake(tokens);
    }

    /**
     * @notice Withdraw service provider tokens once the thawing period has passed.
     * @dev This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will also withdraw.
     */
    function withdraw() external override notPaused {
        _withdraw(msg.sender);
    }

    /*
     * PROVISIONS
     */

    /**
     * @notice Provision stake to a verifier. The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param tokens The amount of tokens that will be locked and slashable
     * @param maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _createProvision(serviceProvider, tokens, verifier, maxVerifierCut, thawingPeriod);
    }

    /**
     * @notice Add more tokens to an existing provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to add to the provision
     */
    function addToProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /**
     * @notice Start thawing tokens to remove them from a provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to thaw
     */
    function thaw(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) returns (bytes32) {
        return _thaw(serviceProvider, verifier, tokens);
    }

    // moves thawed stake from a provision back into the provider's available stake
    function deprovision(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) external override onlyAuthorized(serviceProvider, verifier) notPaused {
        _deprovision(serviceProvider, verifier, nThawRequests);
    }

    /**
     * @notice Move already thawed stake from one provision into another provision
     * This function can be called by the service provider or by an operator authorized by the provider
     * for the two corresponding verifiers.
     * The provider must have previously provisioned tokens to the new verifier.
     * @param serviceProvider The service provider address
     * @param oldVerifier The verifier address for which the tokens are currently provisioned
     * @param newVerifier The verifier address for which the tokens will be provisioned
     * @param tokens The amount of tokens to move
     */
    function reprovision(
        address serviceProvider,
        address oldVerifier,
        address newVerifier,
        uint256 tokens,
        uint256 nThawRequests
    )
        external
        override
        notPaused
        onlyAuthorized(serviceProvider, oldVerifier)
        onlyAuthorized(serviceProvider, newVerifier)
    {
        _deprovision(serviceProvider, oldVerifier, nThawRequests);
        _addToProvision(serviceProvider, newVerifier, tokens);
    }

    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        Provision storage prov = _provisions[serviceProvider][verifier];
        prov.maxVerifierCutPending = maxVerifierCut;
        prov.thawingPeriodPending = thawingPeriod;
        emit ProvisionParametersStaged(serviceProvider, verifier, maxVerifierCut, thawingPeriod);
    }

    function acceptProvisionParameters(address serviceProvider) external override notPaused {
        address verifier = msg.sender;
        Provision storage prov = _provisions[serviceProvider][verifier];
        prov.maxVerifierCut = prov.maxVerifierCutPending;
        prov.thawingPeriod = prov.thawingPeriodPending;
        emit ProvisionParametersSet(serviceProvider, verifier, prov.maxVerifierCut, prov.thawingPeriod);
    }

    /*
     * DELEGATION
     */

    function delegate(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint256 minSharesOut
    ) external override notPaused {
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, verifier, tokens, minSharesOut);
    }

    /**
     * @notice Add tokens to a delegation pool (without getting shares).
     * Used by data services to pay delegation fees/rewards.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     * @param tokens The amount of tokens to add to the delegation pool
     */
    function addToDelegationPool(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused {
        require(tokens != 0, HorizonStakingInvalidZeroTokens());
        DelegationPoolInternal storage pool = _getDelegationPool(serviceProvider, verifier);
        pool.tokens = pool.tokens + tokens;
        emit TokensToDelegationPoolAdded(serviceProvider, verifier, tokens);
    }

    // undelegate tokens from a service provider
    // the shares are burned and replaced with shares in the thawing pool
    function undelegate(
        address serviceProvider,
        address verifier,
        uint256 shares
    ) external override notPaused returns (bytes32) {
        return _undelegate(serviceProvider, verifier, shares);
    }

    function withdrawDelegated(
        address serviceProvider,
        address verifier,
        address newServiceProvider,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) external override notPaused {
        _withdrawDelegated(serviceProvider, verifier, newServiceProvider, minSharesForNewProvider, nThawRequests);
    }

    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _delegationFeeCut[serviceProvider][verifier][paymentType] = feeCut;
        emit DelegationFeeCutSet(serviceProvider, verifier, paymentType, feeCut);
    }

    // For backwards compatibility, delegates to the subgraph data service
    // (Note this one doesn't have splippage/rounding protection!)
    function delegate(address serviceProvider, uint256 tokens) external override notPaused {
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, tokens, 0);
    }

    // For backwards compatibility, undelegates from the subgraph data service
    function undelegate(address serviceProvider, uint256 shares) external override notPaused {
        _undelegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, shares);
    }

    // For backwards compatibility, withdraws delegated tokens from the subgraph data service
    function withdrawDelegated(address serviceProvider, address newServiceProvider) external override notPaused {
        _withdrawDelegated(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, newServiceProvider, 0, 0);
    }

    /*
     * SLASHING
     */

    /**
     * @notice Slash a service provider. This can only be called by a verifier to which
     * the provider has provisioned stake, and up to the amount of tokens they have provisioned.
     * @dev If delegation slashing is disabled, and the amount of tokens is more than the
     * provider's provisioned self-stake, the delegation slashing is skipped without reverting.
     * @param serviceProvider The service provider to slash
     * @param tokens The amount of tokens to slash
     * @param tokensVerifier The amount of tokens to transfer instead of burning
     * @param verifierDestination The address to transfer the verifier cut to
     */
    function slash(
        address serviceProvider,
        uint256 tokens,
        uint256 tokensVerifier,
        address verifierDestination
    ) external override notPaused {
        address verifier = msg.sender;
        Provision storage prov = _provisions[serviceProvider][verifier];
        DelegationPoolInternal storage pool = _getDelegationPool(serviceProvider, verifier);
        uint256 tokensProvisionTotal = prov.tokens + pool.tokens;
        require(tokensProvisionTotal >= tokens, HorizonStakingInsufficientTokens(prov.tokens, tokens));

        uint256 tokensToSlash = tokens;
        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        if (providerTokensSlashed > 0) {
            uint256 maxVerifierCut = prov.tokens.mulPPM(prov.maxVerifierCut);
            require(
                maxVerifierCut >= tokensVerifier,
                HorizonStakingVerifierTokensTooHigh(tokensVerifier, maxVerifierCut)
            );
            if (tokensVerifier > 0) {
                _graphToken().pushTokens(verifierDestination, tokensVerifier);
                emit VerifierTokensSent(serviceProvider, verifier, verifierDestination, tokensVerifier);
            }
            _graphToken().burnTokens(providerTokensSlashed - tokensVerifier);
            uint256 provisionFractionSlashed = (providerTokensSlashed * FIXED_POINT_PRECISION) / prov.tokens;
            // TODO check for rounding issues
            prov.tokensThawing =
                (prov.tokensThawing * (FIXED_POINT_PRECISION - provisionFractionSlashed)) /
                (FIXED_POINT_PRECISION);
            prov.tokens = prov.tokens - providerTokensSlashed;
            _serviceProviders[serviceProvider].tokensProvisioned =
                _serviceProviders[serviceProvider].tokensProvisioned -
                providerTokensSlashed;
            _serviceProviders[serviceProvider].tokensStaked =
                _serviceProviders[serviceProvider].tokensStaked -
                providerTokensSlashed;
            emit ProvisionSlashed(serviceProvider, verifier, providerTokensSlashed);
        }

        tokensToSlash = tokensToSlash - providerTokensSlashed;
        if (tokensToSlash > 0) {
            if (_delegationSlashingEnabled) {
                require(pool.tokens >= tokensToSlash, HorizonStakingNotEnoughDelegation(pool.tokens, tokensToSlash));
                _graphToken().burnTokens(tokensToSlash);
                uint256 delegationFractionSlashed = (tokensToSlash * FIXED_POINT_PRECISION) / pool.tokens;
                pool.tokens = pool.tokens - tokensToSlash;
                pool.tokensThawing =
                    (pool.tokensThawing * (FIXED_POINT_PRECISION - delegationFractionSlashed)) /
                    FIXED_POINT_PRECISION;
                emit DelegationSlashed(serviceProvider, verifier, tokensToSlash);
            } else {
                emit DelegationSlashingSkipped(serviceProvider, verifier, tokensToSlash);
            }
        }
    }

    /*
     * LOCKED VERIFIERS
     */

    /**
     * @notice Provision stake to a verifier using locked tokens (i.e. from GraphTokenLockWallets). The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier. Only authorized verifiers can be used.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param tokens The amount of tokens that will be locked and slashable
     * @param maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function provisionLocked(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        require(_allowedLockedVerifiers[verifier], HorizonStakingVerifierNotAllowed(verifier));
        _createProvision(serviceProvider, tokens, verifier, maxVerifierCut, thawingPeriod);
    }

    // for vesting contracts
    function setOperatorLocked(address operator, address verifier, bool allowed) external override notPaused {
        require(_allowedLockedVerifiers[verifier], HorizonStakingVerifierNotAllowed(verifier));
        _setOperator(operator, verifier, allowed);
    }

    /*
     * GOVERNANCE
     */

    function setAllowedLockedVerifier(address verifier, bool allowed) external override onlyGovernor {
        _allowedLockedVerifiers[verifier] = allowed;
        emit AllowedLockedVerifierSet(verifier, allowed);
    }

    function setDelegationSlashingEnabled(bool enabled) external override onlyGovernor {
        _delegationSlashingEnabled = enabled;
        emit DelegationSlashingEnabled(enabled);
    }

    // To be called at the end of the transition period, to set the deprecated thawing period to 0
    function clearThawingPeriod() external override onlyGovernor {
        __DEPRECATED_thawingPeriod = 0;
        emit ThawingPeriodCleared();
    }

    function setMaxThawingPeriod(uint64 maxThawingPeriod) external override onlyGovernor {
        _maxThawingPeriod = maxThawingPeriod;
        emit MaxThawingPeriodSet(_maxThawingPeriod);
    }

    /*
     * OPERATOR
     */

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param operator Address to authorize or unauthorize
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address operator, address verifier, bool allowed) external override notPaused {
        _setOperator(operator, verifier, allowed);
    }

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @param operator The address to check for auth
     * @param serviceProvider The service provider on behalf of whom they're claiming to act
     * @param verifier The verifier / data service on which they're claiming to act
     */
    function isAuthorized(
        address operator,
        address serviceProvider,
        address verifier
    ) external view override returns (bool) {
        return _isAuthorized(operator, serviceProvider, verifier);
    }

    /*
     * PRIVATE FUNCTIONS
     */
    function _stakeTo(address _serviceProvider, uint256 _tokens) private {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());

        // Transfer tokens to stake from caller to this contract
        _graphToken().pullTokens(msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_serviceProvider, _tokens);
    }

    function _unstake(uint256 _tokens) private {
        address serviceProvider = msg.sender;
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        require(_tokens <= _getIdleStake(serviceProvider), HorizonStakingInsufficientCapacity());

        ServiceProviderInternal storage sp = _serviceProviders[serviceProvider];
        uint256 stakedTokens = sp.tokensStaked;
        // Check that the service provider's stake minus the tokens to unstake is sufficient
        // to cover existing allocations
        // TODO this is only needed until legacy allocations are closed,
        // so we should remove it after the transition period
        require(
            stakedTokens - _tokens >= sp.__DEPRECATED_tokensAllocated,
            HorizonStakingInsufficientCapacityForLegacyAllocations()
        );

        // This is also only during the transition period: we need
        // to ensure tokens stay locked after closing legacy allocations.
        // After sufficient time (56 days?) we should remove the closeAllocation function
        // and set the thawing period to 0.
        uint256 lockingPeriod = __DEPRECATED_thawingPeriod;
        if (lockingPeriod == 0) {
            sp.tokensStaked = stakedTokens - _tokens;
            _graphToken().pushTokens(serviceProvider, _tokens);
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
     * @dev Withdraw service provider tokens once the thawing period has passed.
     * @param _serviceProvider Address of service provider to withdraw funds from
     */
    function _withdraw(address _serviceProvider) private {
        // Get tokens available for withdraw and update balance
        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        uint256 tokensToWithdraw = sp.__DEPRECATED_tokensLocked;
        require(tokensToWithdraw > 0, HorizonStakingInvalidZeroTokens());
        require(
            block.timestamp >= sp.__DEPRECATED_tokensLockedUntil,
            HorizonStakingStillThawing(sp.__DEPRECATED_tokensLockedUntil)
        );

        // Reset locked tokens
        sp.__DEPRECATED_tokensLocked = 0;
        sp.__DEPRECATED_tokensLockedUntil = 0;

        sp.tokensStaked = sp.tokensStaked - tokensToWithdraw;

        // Return tokens to the service provider
        _graphToken().pushTokens(_serviceProvider, tokensToWithdraw);

        emit StakeWithdrawn(_serviceProvider, tokensToWithdraw);
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
    ) private {
        require(_tokens >= MIN_PROVISION_SIZE, HorizonStakingInvalidTokens(_tokens, MIN_PROVISION_SIZE));
        require(
            _maxVerifierCut <= MAX_MAX_VERIFIER_CUT,
            HorizonStakingInvalidMaxVerifierCut(_maxVerifierCut, MAX_MAX_VERIFIER_CUT)
        );
        require(
            _thawingPeriod <= _maxThawingPeriod,
            HorizonStakingInvalidThawingPeriod(_thawingPeriod, _maxThawingPeriod)
        );
        require(_tokens <= _getIdleStake(_serviceProvider), HorizonStakingInsufficientCapacity());

        _provisions[_serviceProvider][_verifier] = Provision({
            tokens: _tokens,
            tokensThawing: 0,
            sharesThawing: 0,
            maxVerifierCut: _maxVerifierCut,
            thawingPeriod: _thawingPeriod,
            createdAt: uint64(block.timestamp),
            maxVerifierCutPending: _maxVerifierCut,
            thawingPeriodPending: _thawingPeriod
        });

        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        sp.tokensProvisioned = sp.tokensProvisioned + _tokens;

        emit ProvisionCreated(_serviceProvider, _verifier, _tokens, _maxVerifierCut, _thawingPeriod);
    }

    function _addToProvision(address _serviceProvider, address _verifier, uint256 _tokens) private {
        Provision storage prov = _provisions[_serviceProvider][_verifier];
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(_serviceProvider, _verifier));
        require(_tokens <= _getIdleStake(_serviceProvider), HorizonStakingInsufficientCapacity());

        prov.tokens = prov.tokens + _tokens;
        _serviceProviders[_serviceProvider].tokensProvisioned =
            _serviceProviders[_serviceProvider].tokensProvisioned +
            _tokens;
        emit ProvisionIncreased(_serviceProvider, _verifier, _tokens);
    }

    function _thaw(address _serviceProvider, address _verifier, uint256 _tokens) private returns (bytes32) {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        uint256 tokensAvailable = _getProviderTokensAvailable(_serviceProvider, _verifier);
        require(tokensAvailable >= _tokens, HorizonStakingInsufficientTokensAvailable(tokensAvailable, _tokens));

        Provision storage prov = _provisions[_serviceProvider][_verifier];
        uint256 thawingShares = prov.sharesThawing == 0 ? _tokens : (prov.sharesThawing * _tokens) / prov.tokensThawing;
        uint64 thawingUntil = uint64(block.timestamp + uint256(prov.thawingPeriod));

        // provision accounting
        prov.tokensThawing = prov.tokensThawing + _tokens;
        prov.sharesThawing = prov.sharesThawing + thawingShares;

        bytes32 thawRequestId = _createThawRequest(
            _serviceProvider,
            _verifier,
            _serviceProvider,
            thawingShares,
            thawingUntil
        );
        emit ProvisionThawed(_serviceProvider, _verifier, _tokens);
        return thawRequestId;
    }

    function _deprovision(address _serviceProvider, address _verifier, uint256 _nThawRequests) private {
        Provision storage prov = _provisions[_serviceProvider][_verifier];

        uint256 tokensThawed = 0;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;
        (tokensThawed, tokensThawing, sharesThawing) = _fulfillThawRequests(
            _serviceProvider,
            _verifier,
            _serviceProvider,
            tokensThawing,
            sharesThawing,
            _nThawRequests
        );

        prov.tokens = prov.tokens - tokensThawed;
        prov.sharesThawing = sharesThawing;
        prov.tokensThawing = tokensThawing;
        _serviceProviders[_serviceProvider].tokensProvisioned -= tokensThawed;

        emit TokensDeprovisioned(_serviceProvider, _verifier, tokensThawed);
    }

    function _delegate(address _serviceProvider, address _verifier, uint256 _tokens, uint256 _minSharesOut) private {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());

        // TODO: remove this after L2 transfer tool for delegation is removed
        require(_tokens >= MIN_DELEGATION, HorizonStakingInsufficientTokens(MIN_DELEGATION, _tokens));
        require(
            _provisions[_serviceProvider][_verifier].tokens != 0,
            HorizonStakingInvalidProvision(_serviceProvider, _verifier)
        );

        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? _tokens : ((_tokens * pool.shares) / (pool.tokens - pool.tokensThawing));
        require(shares != 0 && shares >= _minSharesOut, HorizonStakingSlippageProtection(_minSharesOut, shares));

        pool.tokens = pool.tokens + _tokens;
        pool.shares = pool.shares + shares;

        delegation.shares = delegation.shares + shares;

        emit TokensDelegated(_serviceProvider, _verifier, msg.sender, _tokens);
    }

    function _undelegate(address _serviceProvider, address _verifier, uint256 _shares) private returns (bytes32) {
        require(_shares > 0, HorizonStakingInvalidZeroShares());
        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];
        require(delegation.shares >= _shares, HorizonStakingInvalidSharesAmount(delegation.shares, _shares));

        uint256 tokens = (_shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
        uint256 thawingShares = pool.tokensThawing == 0 ? tokens : ((tokens * pool.sharesThawing) / pool.tokensThawing);
        uint64 thawingUntil = uint64(block.timestamp + uint256(_provisions[_serviceProvider][_verifier].thawingPeriod));
        pool.shares = pool.shares - _shares;
        pool.tokensThawing = pool.tokensThawing + tokens;
        pool.sharesThawing = pool.sharesThawing + thawingShares;

        delegation.shares = delegation.shares - _shares;
        // TODO: remove this when L2 transfer tools are removed
        if (delegation.shares != 0) {
            uint256 remainingTokens = (delegation.shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
            require(
                remainingTokens >= MIN_DELEGATION,
                HorizonStakingInsufficientTokens(remainingTokens, MIN_DELEGATION)
            );
        }

        bytes32 thawRequestId = _createThawRequest(
            _serviceProvider,
            _verifier,
            msg.sender,
            thawingShares,
            thawingUntil
        );

        emit TokensUndelegated(_serviceProvider, _verifier, msg.sender, tokens);
        return thawRequestId;
    }

    function _withdrawDelegated(
        address _serviceProvider,
        address _verifier,
        address _newServiceProvider,
        uint256 _minSharesForNewProvider,
        uint256 _nThawRequests
    ) private {
        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);

        uint256 tokensThawed = 0;
        uint256 sharesThawing = pool.sharesThawing;
        uint256 tokensThawing = pool.tokensThawing;
        (tokensThawed, tokensThawing, sharesThawing) = _fulfillThawRequests(
            _serviceProvider,
            _verifier,
            msg.sender,
            tokensThawing,
            sharesThawing,
            _nThawRequests
        );

        pool.tokens = pool.tokens - tokensThawed;
        pool.sharesThawing = sharesThawing;
        pool.tokensThawing = tokensThawing;

        if (_newServiceProvider != address(0)) {
            _delegate(_newServiceProvider, _verifier, tokensThawed, _minSharesForNewProvider);
        } else {
            _graphToken().pushTokens(msg.sender, tokensThawed);
        }

        emit DelegatedTokensWithdrawn(_serviceProvider, _verifier, msg.sender, tokensThawed);
    }

    function _createThawRequest(
        address _serviceProvider,
        address _verifier,
        address _owner,
        uint256 _shares,
        uint64 _thawingUntil
    ) private returns (bytes32) {
        LinkedList.List storage thawRequestList = _thawRequestLists[_serviceProvider][_verifier][_owner];
        require(thawRequestList.count < MAX_THAW_REQUESTS, HorizonStakingTooManyThawRequests());

        bytes32 thawRequestId = keccak256(abi.encodePacked(_serviceProvider, _verifier, _owner, thawRequestList.nonce));
        _thawRequests[thawRequestId] = ThawRequest({ shares: _shares, thawingUntil: _thawingUntil, next: bytes32(0) });

        if (thawRequestList.count != 0) _thawRequests[thawRequestList.tail].next = thawRequestId;
        thawRequestList.add(thawRequestId);

        emit ThawRequestCreated(_serviceProvider, _verifier, _owner, _shares, _thawingUntil, thawRequestId);
        return thawRequestId;
    }

    function _fulfillThawRequests(
        address _serviceProvider,
        address _verifier,
        address _owner,
        uint256 _tokensThawing,
        uint256 _sharesThawing,
        uint256 _nThawRequests
    ) private returns (uint256, uint256, uint256) {
        LinkedList.List storage thawRequestList = _thawRequestLists[_serviceProvider][_verifier][_owner];
        require(thawRequestList.count > 0, HorizonStakingNothingThawing());

        uint256 tokensThawed = 0;
        (uint256 thawRequestsFulfilled, bytes memory data) = thawRequestList.traverse(
            _getNextThawRequest,
            _fulfillThawRequest,
            _deleteThawRequest,
            abi.encode(tokensThawed, _tokensThawing, _sharesThawing),
            _nThawRequests
        );

        (tokensThawed, _tokensThawing, _sharesThawing) = abi.decode(data, (uint256, uint256, uint256));
        emit ThawRequestsFulfilled(_serviceProvider, _verifier, _owner, thawRequestsFulfilled, tokensThawed);
        return (tokensThawed, _tokensThawing, _sharesThawing);
    }

    function _fulfillThawRequest(bytes32 _thawRequestId, bytes memory _acc) private returns (bool, bool, bytes memory) {
        ThawRequest storage thawRequest = _thawRequests[_thawRequestId];

        // early exit
        if (thawRequest.thawingUntil > block.timestamp) {
            return (true, false, LinkedList.NULL_BYTES);
        }

        // decode
        (uint256 tokensThawed, uint256 tokensThawing, uint256 sharesThawing) = abi.decode(
            _acc,
            (uint256, uint256, uint256)
        );

        // process
        uint256 tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
        tokensThawing = tokensThawing - tokens;
        sharesThawing = sharesThawing - thawRequest.shares;
        tokensThawed = tokensThawed + tokens;
        emit ThawRequestFulfilled(_thawRequestId, tokens, thawRequest.shares, thawRequest.thawingUntil);

        // encode
        _acc = abi.encode(tokensThawed, tokensThawing, sharesThawing);
        return (false, true, _acc);
    }

    function _deleteThawRequest(bytes32 _thawRequestId) private {
        delete _thawRequests[_thawRequestId];
    }

    function _setOperator(address _operator, address _verifier, bool _allowed) private {
        require(_operator != msg.sender, HorizonStakingCallerIsServiceProvider());
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            _legacyOperatorAuth[msg.sender][_operator] = _allowed;
        } else {
            _operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        }
        emit OperatorSet(msg.sender, _operator, _verifier, _allowed);
    }

    function _isAuthorized(address _operator, address _serviceProvider, address _verifier) private view returns (bool) {
        if (_operator == _serviceProvider) {
            return true;
        }
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return _legacyOperatorAuth[_serviceProvider][_operator];
        } else {
            return _operatorAuth[_serviceProvider][_verifier][_operator];
        }
    }
}
