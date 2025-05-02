// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStakingMain } from "../interfaces/internal/IHorizonStakingMain.sol";
import { IHorizonStakingExtension } from "../interfaces/internal/IHorizonStakingExtension.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { MathUtils } from "../libraries/MathUtils.sol";
import { PPMMath } from "../libraries/PPMMath.sol";
import { LinkedList } from "../libraries/LinkedList.sol";

import { HorizonStakingBase } from "./HorizonStakingBase.sol";

/**
 * @title HorizonStaking contract
 * @notice The {HorizonStaking} contract allows service providers to stake and provision tokens to verifiers to be used
 * as economic security for a service. It also allows delegators to delegate towards a service provider provision.
 * @dev Implements the {IHorizonStakingMain} interface.
 * @dev This is the main Staking contract in The Graph protocol after the Horizon upgrade.
 * It is designed to be deployed as an upgrade to the L2Staking contract from the legacy contracts package.
 * @dev It uses a {HorizonStakingExtension} contract to implement the full {IHorizonStaking} interface through delegatecalls.
 * This is due to the contract size limit on Arbitrum (24kB). The extension contract implements functionality to support
 * the legacy staking functions. It can be eventually removed without affecting the main staking contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract HorizonStaking is HorizonStakingBase, IHorizonStakingMain {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;
    using LinkedList for LinkedList.List;

    /// @dev Maximum number of simultaneous stake thaw requests (per provision) or undelegations (per delegation)
    uint256 private constant MAX_THAW_REQUESTS = 1_000;

    /// @dev Address of the staking extension contract
    address private immutable STAKING_EXTENSION_ADDRESS;

    /// @dev Minimum amount of delegation.
    uint256 private constant MIN_DELEGATION = 1e18;

    /**
     * @notice Checks that the caller is authorized to operate over a provision.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     */
    modifier onlyAuthorized(address serviceProvider, address verifier) {
        require(
            _isAuthorized(serviceProvider, verifier, msg.sender),
            HorizonStakingNotAuthorized(serviceProvider, verifier, msg.sender)
        );
        _;
    }

    /**
     * @notice Checks that the caller is authorized to operate over a provision or it is the verifier.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     */
    modifier onlyAuthorizedOrVerifier(address serviceProvider, address verifier) {
        require(
            _isAuthorized(serviceProvider, verifier, msg.sender) || msg.sender == verifier,
            HorizonStakingNotAuthorized(serviceProvider, verifier, msg.sender)
        );
        _;
    }

    /**
     * @dev The staking contract is upgradeable however we still use the constructor to set
     * a few immutable variables.
     * @param controller The address of the Graph controller contract.
     * @param stakingExtensionAddress The address of the staking extension contract.
     * @param subgraphDataServiceAddress The address of the subgraph data service.
     */
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

    /// @inheritdoc IHorizonStakingMain
    function stake(uint256 tokens) external override notPaused {
        _stakeTo(msg.sender, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function stakeTo(address serviceProvider, uint256 tokens) external override notPaused {
        _stakeTo(serviceProvider, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function stakeToProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorizedOrVerifier(serviceProvider, verifier) {
        _stakeTo(serviceProvider, tokens);
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function unstake(uint256 tokens) external override notPaused {
        _unstake(tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function withdraw() external override notPaused {
        _withdraw(msg.sender);
    }

    /*
     * PROVISIONS
     */

    /// @inheritdoc IHorizonStakingMain
    function provision(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _createProvision(serviceProvider, tokens, verifier, maxVerifierCut, thawingPeriod);
    }

    /// @inheritdoc IHorizonStakingMain
    function addToProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function thaw(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) returns (bytes32) {
        return _thaw(serviceProvider, verifier, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function deprovision(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) external override onlyAuthorized(serviceProvider, verifier) notPaused {
        _deprovision(serviceProvider, verifier, nThawRequests);
    }

    /// @inheritdoc IHorizonStakingMain
    function reprovision(
        address serviceProvider,
        address oldVerifier,
        address newVerifier,
        uint256 nThawRequests
    )
        external
        override
        notPaused
        onlyAuthorized(serviceProvider, oldVerifier)
        onlyAuthorized(serviceProvider, newVerifier)
    {
        uint256 tokensThawed = _deprovision(serviceProvider, oldVerifier, nThawRequests);
        _addToProvision(serviceProvider, newVerifier, tokensThawed);
    }

    /// @inheritdoc IHorizonStakingMain
    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 newMaxVerifierCut,
        uint64 newThawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        // Provision must exist
        Provision storage prov = _provisions[serviceProvider][verifier];
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(serviceProvider, verifier));

        bool verifierCutChanged = prov.maxVerifierCutPending != newMaxVerifierCut;
        bool thawingPeriodChanged = prov.thawingPeriodPending != newThawingPeriod;

        if (verifierCutChanged || thawingPeriodChanged) {
            if (verifierCutChanged) {
                require(PPMMath.isValidPPM(newMaxVerifierCut), HorizonStakingInvalidMaxVerifierCut(newMaxVerifierCut));
                prov.maxVerifierCutPending = newMaxVerifierCut;
            }
            if (thawingPeriodChanged) {
                require(
                    newThawingPeriod <= _maxThawingPeriod,
                    HorizonStakingInvalidThawingPeriod(newThawingPeriod, _maxThawingPeriod)
                );
                prov.thawingPeriodPending = newThawingPeriod;
            }

            prov.lastParametersStagedAt = block.timestamp;
            emit ProvisionParametersStaged(serviceProvider, verifier, newMaxVerifierCut, newThawingPeriod);
        }
    }

    /// @inheritdoc IHorizonStakingMain
    function acceptProvisionParameters(address serviceProvider) external override notPaused {
        address verifier = msg.sender;

        // Provision must exist
        Provision storage prov = _provisions[serviceProvider][verifier];
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(serviceProvider, verifier));

        if ((prov.maxVerifierCutPending != prov.maxVerifierCut) || (prov.thawingPeriodPending != prov.thawingPeriod)) {
            prov.maxVerifierCut = prov.maxVerifierCutPending;
            prov.thawingPeriod = prov.thawingPeriodPending;
            emit ProvisionParametersSet(serviceProvider, verifier, prov.maxVerifierCut, prov.thawingPeriod);
        }
    }

    /*
     * DELEGATION
     */

    /// @inheritdoc IHorizonStakingMain
    function delegate(
        address serviceProvider,
        address verifier,
        uint256 tokens,
        uint256 minSharesOut
    ) external override notPaused {
        require(tokens != 0, HorizonStakingInvalidZeroTokens());
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, verifier, tokens, minSharesOut);
    }

    /// @inheritdoc IHorizonStakingMain
    function addToDelegationPool(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused {
        require(tokens != 0, HorizonStakingInvalidZeroTokens());

        // Provision must exist before adding to delegation pool
        Provision memory prov = _provisions[serviceProvider][verifier];
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(serviceProvider, verifier));

        // Delegation pool must exist before adding tokens
        DelegationPoolInternal storage pool = _getDelegationPool(serviceProvider, verifier);
        require(pool.shares > 0, HorizonStakingInvalidDelegationPool(serviceProvider, verifier));

        pool.tokens = pool.tokens + tokens;
        _graphToken().pullTokens(msg.sender, tokens);
        emit TokensToDelegationPoolAdded(serviceProvider, verifier, tokens);
    }

    /// @inheritdoc IHorizonStakingMain
    function undelegate(
        address serviceProvider,
        address verifier,
        uint256 shares
    ) external override notPaused returns (bytes32) {
        return _undelegate(serviceProvider, verifier, shares);
    }

    /// @inheritdoc IHorizonStakingMain
    function withdrawDelegated(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) external override notPaused {
        _withdrawDelegated(serviceProvider, verifier, address(0), address(0), 0, nThawRequests);
    }

    /// @inheritdoc IHorizonStakingMain
    function redelegate(
        address oldServiceProvider,
        address oldVerifier,
        address newServiceProvider,
        address newVerifier,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) external override notPaused {
        require(newServiceProvider != address(0), HorizonStakingInvalidServiceProviderZeroAddress());
        require(newVerifier != address(0), HorizonStakingInvalidVerifierZeroAddress());
        _withdrawDelegated(
            oldServiceProvider,
            oldVerifier,
            newServiceProvider,
            newVerifier,
            minSharesForNewProvider,
            nThawRequests
        );
    }

    /// @inheritdoc IHorizonStakingMain
    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType,
        uint256 feeCut
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        require(PPMMath.isValidPPM(feeCut), HorizonStakingInvalidDelegationFeeCut(feeCut));
        _delegationFeeCut[serviceProvider][verifier][paymentType] = feeCut;
        emit DelegationFeeCutSet(serviceProvider, verifier, paymentType, feeCut);
    }

    /// @inheritdoc IHorizonStakingMain
    function delegate(address serviceProvider, uint256 tokens) external override notPaused {
        require(tokens != 0, HorizonStakingInvalidZeroTokens());
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, tokens, 0);
    }

    /// @inheritdoc IHorizonStakingMain
    function undelegate(address serviceProvider, uint256 shares) external override notPaused {
        _undelegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, shares);
    }

    /// @inheritdoc IHorizonStakingMain
    function withdrawDelegated(
        address serviceProvider,
        address // deprecated - kept for backwards compatibility
    ) external override notPaused returns (uint256) {
        // Get the delegation pool of the indexer
        address delegator = msg.sender;
        DelegationPoolInternal storage pool = _legacyDelegationPools[serviceProvider];
        DelegationInternal storage delegation = pool.delegators[delegator];

        // Validation
        uint256 tokensToWithdraw = 0;
        uint256 currentEpoch = _graphEpochManager().currentEpoch();
        if (
            delegation.__DEPRECATED_tokensLockedUntil > 0 && currentEpoch >= delegation.__DEPRECATED_tokensLockedUntil
        ) {
            tokensToWithdraw = delegation.__DEPRECATED_tokensLocked;
        }
        require(tokensToWithdraw > 0, HorizonStakingNothingToWithdraw());

        // Reset lock
        delegation.__DEPRECATED_tokensLocked = 0;
        delegation.__DEPRECATED_tokensLockedUntil = 0;

        emit StakeDelegatedWithdrawn(serviceProvider, delegator, tokensToWithdraw);

        // -- Interactions --

        // Return tokens to the delegator
        _graphToken().pushTokens(delegator, tokensToWithdraw);

        return tokensToWithdraw;
    }

    /*
     * SLASHING
     */

    /// @inheritdoc IHorizonStakingMain
    function slash(
        address serviceProvider,
        uint256 tokens,
        uint256 tokensVerifier,
        address verifierDestination
    ) external override notPaused {
        // TRANSITION PERIOD: remove after the transition period
        // Check if sender is authorized to slash on the deprecated list
        if (__DEPRECATED_slashers[msg.sender]) {
            // Forward call to staking extension
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = STAKING_EXTENSION_ADDRESS.delegatecall(
                abi.encodeCall(
                    IHorizonStakingExtension.legacySlash,
                    (serviceProvider, tokens, tokensVerifier, verifierDestination)
                )
            );
            require(success, HorizonStakingLegacySlashFailed());
            return;
        }

        address verifier = msg.sender;
        Provision storage prov = _provisions[serviceProvider][verifier];
        DelegationPoolInternal storage pool = _getDelegationPool(serviceProvider, verifier);
        uint256 tokensProvisionTotal = prov.tokens + pool.tokens;
        require(tokensProvisionTotal != 0, HorizonStakingNoTokensToSlash());

        uint256 tokensToSlash = MathUtils.min(tokens, tokensProvisionTotal);

        // Slash service provider first
        // - A portion goes to verifier as reward
        // - A portion gets burned
        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        if (providerTokensSlashed > 0) {
            // Pay verifier reward - must be within the maxVerifierCut percentage
            uint256 maxVerifierTokens = providerTokensSlashed.mulPPM(prov.maxVerifierCut);
            require(
                maxVerifierTokens >= tokensVerifier,
                HorizonStakingTooManyTokens(tokensVerifier, maxVerifierTokens)
            );
            if (tokensVerifier > 0) {
                _graphToken().pushTokens(verifierDestination, tokensVerifier);
                emit VerifierTokensSent(serviceProvider, verifier, verifierDestination, tokensVerifier);
            }

            // Burn remainder
            _graphToken().burnTokens(providerTokensSlashed - tokensVerifier);

            // Provision accounting - round down, 1 wei max precision loss
            prov.tokensThawing = (prov.tokensThawing * (prov.tokens - providerTokensSlashed)) / prov.tokens;
            prov.tokens = prov.tokens - providerTokensSlashed;

            // If the slashing leaves the thawing shares with no thawing tokens, cancel pending thawings by:
            // - deleting all thawing shares
            // - incrementing the nonce to invalidate pending thaw requests
            if (prov.sharesThawing != 0 && prov.tokensThawing == 0) {
                prov.sharesThawing = 0;
                prov.thawingNonce++;
            }

            // Service provider accounting
            _serviceProviders[serviceProvider].tokensProvisioned =
                _serviceProviders[serviceProvider].tokensProvisioned -
                providerTokensSlashed;
            _serviceProviders[serviceProvider].tokensStaked =
                _serviceProviders[serviceProvider].tokensStaked -
                providerTokensSlashed;

            emit ProvisionSlashed(serviceProvider, verifier, providerTokensSlashed);
        }

        // Slash delegators if needed
        // - Slashed delegation is entirely burned
        // Since tokensToSlash is already limited above, this subtraction will remain within pool.tokens.
        tokensToSlash = tokensToSlash - providerTokensSlashed;
        if (tokensToSlash > 0) {
            if (_delegationSlashingEnabled) {
                // Burn tokens
                _graphToken().burnTokens(tokensToSlash);

                // Delegation pool accounting - round down, 1 wei max precision loss
                pool.tokensThawing = (pool.tokensThawing * (pool.tokens - tokensToSlash)) / pool.tokens;
                pool.tokens = pool.tokens - tokensToSlash;

                // If the slashing leaves the thawing shares with no thawing tokens, cancel pending thawings by:
                // - deleting all thawing shares
                // - incrementing the nonce to invalidate pending thaw requests
                // Note that thawing shares are completely lost, delegators won't get back the corresponding
                // delegation pool shares.
                if (pool.sharesThawing != 0 && pool.tokensThawing == 0) {
                    pool.sharesThawing = 0;
                    pool.thawingNonce++;
                }

                emit DelegationSlashed(serviceProvider, verifier, tokensToSlash);
            } else {
                emit DelegationSlashingSkipped(serviceProvider, verifier, tokensToSlash);
            }
        }
    }

    /*
     * LOCKED VERIFIERS
     */

    /// @inheritdoc IHorizonStakingMain
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

    /// @inheritdoc IHorizonStakingMain
    function setOperatorLocked(address verifier, address operator, bool allowed) external override notPaused {
        require(_allowedLockedVerifiers[verifier], HorizonStakingVerifierNotAllowed(verifier));
        _setOperator(verifier, operator, allowed);
    }

    /*
     * GOVERNANCE
     */

    /// @inheritdoc IHorizonStakingMain
    function setAllowedLockedVerifier(address verifier, bool allowed) external override onlyGovernor {
        _allowedLockedVerifiers[verifier] = allowed;
        emit AllowedLockedVerifierSet(verifier, allowed);
    }

    /// @inheritdoc IHorizonStakingMain
    function setDelegationSlashingEnabled() external override onlyGovernor {
        _delegationSlashingEnabled = true;
        emit DelegationSlashingEnabled();
    }

    /// @inheritdoc IHorizonStakingMain
    function clearThawingPeriod() external override onlyGovernor {
        __DEPRECATED_thawingPeriod = 0;
        emit ThawingPeriodCleared();
    }

    /// @inheritdoc IHorizonStakingMain
    function setMaxThawingPeriod(uint64 maxThawingPeriod) external override onlyGovernor {
        _maxThawingPeriod = maxThawingPeriod;
        emit MaxThawingPeriodSet(_maxThawingPeriod);
    }

    /*
     * OPERATOR
     */

    /// @inheritdoc IHorizonStakingMain
    function setOperator(address verifier, address operator, bool allowed) external override notPaused {
        _setOperator(verifier, operator, allowed);
    }

    /// @inheritdoc IHorizonStakingMain
    function isAuthorized(
        address serviceProvider,
        address verifier,
        address operator
    ) external view override returns (bool) {
        return _isAuthorized(serviceProvider, verifier, operator);
    }

    /*
     * GETTERS
     */

    /// @inheritdoc IHorizonStakingMain
    function getStakingExtension() external view override returns (address) {
        return STAKING_EXTENSION_ADDRESS;
    }

    /*
     * PRIVATE FUNCTIONS
     */

    /**
     * @notice Deposit tokens on the service provider stake, on behalf of the service provider.
     * @dev Pulls tokens from the caller.
     * @param _serviceProvider Address of the service provider
     * @param _tokens Amount of tokens to stake
     */
    function _stakeTo(address _serviceProvider, uint256 _tokens) private {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());

        // Transfer tokens to stake from caller to this contract
        _graphToken().pullTokens(msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_serviceProvider, _tokens);
    }

    /**
     * @notice Move idle stake back to the owner's account.
     * Stake is removed from the protocol:
     * - During the transition period it's locked for a period of time before it can be withdrawn
     *   by calling {withdraw}.
     * - After the transition period it's immediately withdrawn.
     * Note that after the transition period if there are tokens still locked they will have to be
     * withdrawn by calling {withdraw}.
     * @param _tokens Amount of tokens to unstake
     */
    function _unstake(uint256 _tokens) private {
        address serviceProvider = msg.sender;
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        uint256 tokensIdle = _getIdleStake(serviceProvider);
        require(_tokens <= tokensIdle, HorizonStakingInsufficientIdleStake(_tokens, tokensIdle));

        ServiceProviderInternal storage sp = _serviceProviders[serviceProvider];
        uint256 stakedTokens = sp.tokensStaked;

        // This is also only during the transition period: we need
        // to ensure tokens stay locked after closing legacy allocations.
        // After sufficient time (56 days?) we should remove the closeAllocation function
        // and set the thawing period to 0.
        uint256 lockingPeriod = __DEPRECATED_thawingPeriod;
        if (lockingPeriod == 0) {
            sp.tokensStaked = stakedTokens - _tokens;
            _graphToken().pushTokens(serviceProvider, _tokens);
            emit HorizonStakeWithdrawn(serviceProvider, _tokens);
        } else {
            // Before locking more tokens, withdraw any unlocked ones if possible
            if (sp.__DEPRECATED_tokensLocked != 0 && block.number >= sp.__DEPRECATED_tokensLockedUntil) {
                _withdraw(serviceProvider);
            }
            // TRANSITION PERIOD: remove after the transition period
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
            emit HorizonStakeLocked(serviceProvider, sp.__DEPRECATED_tokensLocked, sp.__DEPRECATED_tokensLockedUntil);
        }
    }

    /**
     * @notice Withdraw service provider tokens once the thawing period (initiated by {unstake}) has passed.
     * All thawed tokens are withdrawn.
     * @dev TRANSITION PERIOD: This is only needed during the transition period while we still have
     * a global lock. After that, unstake() will automatically withdraw.
     * @param _serviceProvider Address of service provider to withdraw funds from
     */
    function _withdraw(address _serviceProvider) private {
        // Get tokens available for withdraw and update balance
        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        uint256 tokensToWithdraw = sp.__DEPRECATED_tokensLocked;
        require(tokensToWithdraw != 0, HorizonStakingInvalidZeroTokens());
        require(
            block.number >= sp.__DEPRECATED_tokensLockedUntil,
            HorizonStakingStillThawing(sp.__DEPRECATED_tokensLockedUntil)
        );

        // Reset locked tokens
        sp.__DEPRECATED_tokensLocked = 0;
        sp.__DEPRECATED_tokensLockedUntil = 0;

        sp.tokensStaked = sp.tokensStaked - tokensToWithdraw;

        // Return tokens to the service provider
        _graphToken().pushTokens(_serviceProvider, tokensToWithdraw);

        emit HorizonStakeWithdrawn(_serviceProvider, tokensToWithdraw);
    }

    /**
     * @notice Provision stake to a verifier. The tokens will be locked with a thawing period
     * and will be slashable by the verifier. This is the main mechanism to provision stake to a data
     * service, where the data service is the verifier.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     * @dev TRANSITION PERIOD: During the transition period, only the subgraph data service can be used as a verifier. This
     * prevents an escape hatch for legacy allocation stake.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned (who will be able to slash the tokens)
     * @param _tokens The amount of tokens that will be locked and slashable
     * @param _maxVerifierCut The maximum cut, expressed in PPM, that a verifier can transfer instead of burning when slashing
     * @param _thawingPeriod The period in seconds that the tokens will be thawing before they can be removed from the provision
     */
    function _createProvision(
        address _serviceProvider,
        uint256 _tokens,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) private {
        require(_tokens > 0, HorizonStakingInvalidZeroTokens());
        // TRANSITION PERIOD: Remove this after the transition period - it prevents an early escape hatch for legacy allocations
        require(
            _verifier == SUBGRAPH_DATA_SERVICE_ADDRESS || __DEPRECATED_thawingPeriod == 0,
            HorizonStakingInvalidVerifier(_verifier)
        );
        require(PPMMath.isValidPPM(_maxVerifierCut), HorizonStakingInvalidMaxVerifierCut(_maxVerifierCut));
        require(
            _thawingPeriod <= _maxThawingPeriod,
            HorizonStakingInvalidThawingPeriod(_thawingPeriod, _maxThawingPeriod)
        );
        require(_provisions[_serviceProvider][_verifier].createdAt == 0, HorizonStakingProvisionAlreadyExists());
        uint256 tokensIdle = _getIdleStake(_serviceProvider);
        require(_tokens <= tokensIdle, HorizonStakingInsufficientIdleStake(_tokens, tokensIdle));

        _provisions[_serviceProvider][_verifier] = Provision({
            tokens: _tokens,
            tokensThawing: 0,
            sharesThawing: 0,
            maxVerifierCut: _maxVerifierCut,
            thawingPeriod: _thawingPeriod,
            createdAt: uint64(block.timestamp),
            maxVerifierCutPending: _maxVerifierCut,
            thawingPeriodPending: _thawingPeriod,
            lastParametersStagedAt: 0,
            thawingNonce: 0
        });

        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        sp.tokensProvisioned = sp.tokensProvisioned + _tokens;

        emit ProvisionCreated(_serviceProvider, _verifier, _tokens, _maxVerifierCut, _thawingPeriod);
    }

    /**
     * @notice Adds tokens from the service provider's idle stake to a provision
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address
     * @param _tokens The amount of tokens to add to the provision
     */
    function _addToProvision(address _serviceProvider, address _verifier, uint256 _tokens) private {
        Provision storage prov = _provisions[_serviceProvider][_verifier];
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(_serviceProvider, _verifier));
        uint256 tokensIdle = _getIdleStake(_serviceProvider);
        require(_tokens <= tokensIdle, HorizonStakingInsufficientIdleStake(_tokens, tokensIdle));

        prov.tokens = prov.tokens + _tokens;
        _serviceProviders[_serviceProvider].tokensProvisioned =
            _serviceProviders[_serviceProvider].tokensProvisioned +
            _tokens;
        emit ProvisionIncreased(_serviceProvider, _verifier, _tokens);
    }

    /**
     * @notice Start thawing tokens to remove them from a provision.
     * This function can be called by the service provider or by an operator authorized by the provider
     * for this specific verifier.
     *
     * Note that removing tokens from a provision is a two step process:
     * - First the tokens are thawed using this function.
     * - Then after the thawing period, the tokens are removed from the provision using {deprovision}
     *   or {reprovision}.
     *
     * @dev We use a thawing pool to keep track of tokens thawing for multiple thaw requests.
     * If due to slashing the thawing pool loses all of its tokens, the pool is reset and all pending thaw
     * requests are invalidated.
     *
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address for which the tokens are provisioned
     * @param _tokens The amount of tokens to thaw
     * @return The ID of the thaw request
     */
    function _thaw(address _serviceProvider, address _verifier, uint256 _tokens) private returns (bytes32) {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        uint256 tokensAvailable = _getProviderTokensAvailable(_serviceProvider, _verifier);
        require(tokensAvailable >= _tokens, HorizonStakingInsufficientTokens(tokensAvailable, _tokens));

        Provision storage prov = _provisions[_serviceProvider][_verifier];

        // Calculate shares to issue
        // Thawing pool is reset/initialized when the pool is empty: prov.tokensThawing == 0
        // Round thawing shares up to ensure fairness and avoid undervaluing the shares due to rounding down.
        uint256 thawingShares = prov.tokensThawing == 0
            ? _tokens
            : ((prov.sharesThawing * _tokens + prov.tokensThawing - 1) / prov.tokensThawing);
        uint64 thawingUntil = uint64(block.timestamp + uint256(prov.thawingPeriod));

        prov.sharesThawing = prov.sharesThawing + thawingShares;
        prov.tokensThawing = prov.tokensThawing + _tokens;

        bytes32 thawRequestId = _createThawRequest(
            ThawRequestType.Provision,
            _serviceProvider,
            _verifier,
            _serviceProvider,
            thawingShares,
            thawingUntil,
            prov.thawingNonce
        );
        emit ProvisionThawed(_serviceProvider, _verifier, _tokens);
        return thawRequestId;
    }

    /**
     * @notice Remove tokens from a provision and move them back to the service provider's idle stake.
     * @dev The parameter `nThawRequests` can be set to a non zero value to fulfill a specific number of thaw
     * requests in the event that fulfilling all of them results in a gas limit error. Otherwise, the function
     * will attempt to fulfill all thaw requests until the first one that is not yet expired is found.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address
     * @param _nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     * @return The amount of tokens that were removed from the provision
     */
    function _deprovision(
        address _serviceProvider,
        address _verifier,
        uint256 _nThawRequests
    ) private returns (uint256) {
        Provision storage prov = _provisions[_serviceProvider][_verifier];

        uint256 tokensThawed_ = 0;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;

        FulfillThawRequestsParams memory params = FulfillThawRequestsParams({
            requestType: ThawRequestType.Provision,
            serviceProvider: _serviceProvider,
            verifier: _verifier,
            owner: _serviceProvider,
            tokensThawing: tokensThawing,
            sharesThawing: sharesThawing,
            nThawRequests: _nThawRequests,
            thawingNonce: prov.thawingNonce
        });
        (tokensThawed_, tokensThawing, sharesThawing) = _fulfillThawRequests(params);

        prov.tokens = prov.tokens - tokensThawed_;
        prov.sharesThawing = sharesThawing;
        prov.tokensThawing = tokensThawing;
        _serviceProviders[_serviceProvider].tokensProvisioned -= tokensThawed_;

        emit TokensDeprovisioned(_serviceProvider, _verifier, tokensThawed_);
        return tokensThawed_;
    }

    /**
     * @notice Delegate tokens to a provision.
     * @dev Note that this function does not pull the delegated tokens from the caller. It expects that to
     * have been done before calling this function.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address
     * @param _tokens The amount of tokens to delegate
     * @param _minSharesOut The minimum amount of shares to accept, slippage protection.
     */
    function _delegate(address _serviceProvider, address _verifier, uint256 _tokens, uint256 _minSharesOut) private {
        // Enforces a minimum delegation amount to prevent share manipulation attacks.
        // This stops attackers from inflating share value and blocking other delegators.
        require(_tokens >= MIN_DELEGATION, HorizonStakingInsufficientDelegationTokens(_tokens, MIN_DELEGATION));
        require(
            _provisions[_serviceProvider][_verifier].createdAt != 0,
            HorizonStakingInvalidProvision(_serviceProvider, _verifier)
        );

        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];

        // An invalid delegation pool has shares but no tokens
        require(
            pool.tokens != 0 || pool.shares == 0,
            HorizonStakingInvalidDelegationPoolState(_serviceProvider, _verifier)
        );

        // Calculate shares to issue
        // Delegation pool is reset/initialized in any of the following cases:
        // - pool.tokens == 0 and pool.shares == 0, pool is completely empty. Note that we don't test shares == 0 because
        //   the invalid delegation pool check already ensures shares are 0 if tokens are 0
        // - pool.tokens == pool.tokensThawing, the entire pool is thawing
        bool initializePool = pool.tokens == 0 || pool.tokens == pool.tokensThawing;
        uint256 shares = initializePool ? _tokens : ((_tokens * pool.shares) / (pool.tokens - pool.tokensThawing));
        require(shares != 0 && shares >= _minSharesOut, HorizonStakingSlippageProtection(shares, _minSharesOut));

        pool.tokens = pool.tokens + _tokens;
        pool.shares = pool.shares + shares;

        delegation.shares = delegation.shares + shares;

        emit TokensDelegated(_serviceProvider, _verifier, msg.sender, _tokens, shares);
    }

    /**
     * @notice Undelegate tokens from a provision and start thawing them.
     * Note that undelegating tokens from a provision is a two step process:
     * - First the tokens are thawed using this function.
     * - Then after the thawing period, the tokens are removed from the provision using {withdrawDelegated}.
     * @dev To allow delegation to be slashable even while thawing without breaking accounting
     * the delegation pool shares are burned and replaced with thawing pool shares.
     * @dev Note that due to slashing the delegation pool can enter an invalid state if all it's tokens are slashed.
     * An invalid pool can only be recovered by adding back tokens into the pool with {IHorizonStakingMain-addToDelegationPool}.
     * Any time the delegation pool is invalidated, the thawing pool is also reset and any pending undelegate requests get
     * invalidated.
     * @dev Note that delegation that is caught thawing when the pool is invalidated will be completely lost! However delegation shares
     * that were not thawing will be preserved.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address
     * @param _shares The amount of shares to undelegate
     * @return The ID of the thaw request
     */
    function _undelegate(address _serviceProvider, address _verifier, uint256 _shares) private returns (bytes32) {
        require(_shares > 0, HorizonStakingInvalidZeroShares());
        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];
        require(delegation.shares >= _shares, HorizonStakingInsufficientShares(delegation.shares, _shares));

        // An invalid delegation pool has shares but no tokens (previous require check ensures shares > 0)
        require(pool.tokens != 0, HorizonStakingInvalidDelegationPoolState(_serviceProvider, _verifier));

        // Calculate thawing shares to issue - convert delegation pool shares to thawing pool shares
        // delegation pool shares -> delegation pool tokens -> thawing pool shares
        // Thawing pool is reset/initialized when the pool is empty: prov.tokensThawing == 0
        uint256 tokens = (_shares * (pool.tokens - pool.tokensThawing)) / pool.shares;

        // Thawing shares are rounded down to protect the pool and avoid taking extra tokens from other participants.
        uint256 thawingShares = pool.tokensThawing == 0 ? tokens : ((tokens * pool.sharesThawing) / pool.tokensThawing);
        uint64 thawingUntil = uint64(block.timestamp + uint256(_provisions[_serviceProvider][_verifier].thawingPeriod));

        pool.tokensThawing = pool.tokensThawing + tokens;
        pool.sharesThawing = pool.sharesThawing + thawingShares;

        pool.shares = pool.shares - _shares;
        delegation.shares = delegation.shares - _shares;
        if (delegation.shares != 0) {
            uint256 remainingTokens = (delegation.shares * (pool.tokens - pool.tokensThawing)) / pool.shares;
            require(
                remainingTokens >= MIN_DELEGATION,
                HorizonStakingInsufficientTokens(remainingTokens, MIN_DELEGATION)
            );
        }

        bytes32 thawRequestId = _createThawRequest(
            ThawRequestType.Delegation,
            _serviceProvider,
            _verifier,
            msg.sender,
            thawingShares,
            thawingUntil,
            pool.thawingNonce
        );

        emit TokensUndelegated(_serviceProvider, _verifier, msg.sender, tokens, _shares);
        return thawRequestId;
    }

    /**
     * @notice Withdraw undelegated tokens from a provision after thawing.
     * @dev The parameter `nThawRequests` can be set to a non zero value to fulfill a specific number of thaw
     * requests in the event that fulfilling all of them results in a gas limit error. Otherwise, the function
     * will attempt to fulfill all thaw requests until the first one that is not yet expired is found.
     * @dev If the delegation pool was completely slashed before withdrawing, calling this function will fulfill
     * the thaw requests with an amount equal to zero.
     * @param _serviceProvider The service provider address
     * @param _verifier The verifier address
     * @param _newServiceProvider The new service provider address
     * @param _newVerifier The new verifier address
     * @param _minSharesForNewProvider The minimum number of shares for the new service provider
     * @param _nThawRequests The number of thaw requests to fulfill. Set to 0 to fulfill all thaw requests.
     */
    function _withdrawDelegated(
        address _serviceProvider,
        address _verifier,
        address _newServiceProvider,
        address _newVerifier,
        uint256 _minSharesForNewProvider,
        uint256 _nThawRequests
    ) private {
        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);

        // An invalid delegation pool has shares but no tokens
        require(
            pool.tokens != 0 || pool.shares == 0,
            HorizonStakingInvalidDelegationPoolState(_serviceProvider, _verifier)
        );

        uint256 tokensThawed = 0;
        uint256 sharesThawing = pool.sharesThawing;
        uint256 tokensThawing = pool.tokensThawing;

        FulfillThawRequestsParams memory params = FulfillThawRequestsParams({
            requestType: ThawRequestType.Delegation,
            serviceProvider: _serviceProvider,
            verifier: _verifier,
            owner: msg.sender,
            tokensThawing: tokensThawing,
            sharesThawing: sharesThawing,
            nThawRequests: _nThawRequests,
            thawingNonce: pool.thawingNonce
        });
        (tokensThawed, tokensThawing, sharesThawing) = _fulfillThawRequests(params);

        // The next subtraction should never revert becase: pool.tokens >= pool.tokensThawing and pool.tokensThawing >= tokensThawed
        // In the event the pool gets completely slashed tokensThawed will fulfil to 0.
        pool.tokens = pool.tokens - tokensThawed;
        pool.sharesThawing = sharesThawing;
        pool.tokensThawing = tokensThawing;

        if (tokensThawed != 0) {
            if (_newServiceProvider != address(0) && _newVerifier != address(0)) {
                _delegate(_newServiceProvider, _newVerifier, tokensThawed, _minSharesForNewProvider);
            } else {
                _graphToken().pushTokens(msg.sender, tokensThawed);
                emit DelegatedTokensWithdrawn(_serviceProvider, _verifier, msg.sender, tokensThawed);
            }
        }
    }

    /**
     * @notice Creates a thaw request.
     * Allows creating thaw requests up to a maximum of `MAX_THAW_REQUESTS` per owner.
     * Thaw requests are stored in a linked list per owner (and service provider, verifier) to allow for efficient
     * processing.
     * @param _requestType The type of thaw request.
     * @param _serviceProvider The address of the service provider
     * @param _verifier The address of the verifier
     * @param _owner The address of the owner of the thaw request
     * @param _shares The number of shares to thaw
     * @param _thawingUntil The timestamp until which the shares are thawing
     * @param _thawingNonce Owner's validity nonce for the thaw request
     * @return The ID of the thaw request
     */
    function _createThawRequest(
        ThawRequestType _requestType,
        address _serviceProvider,
        address _verifier,
        address _owner,
        uint256 _shares,
        uint64 _thawingUntil,
        uint256 _thawingNonce
    ) private returns (bytes32) {
        require(_shares != 0, HorizonStakingInvalidZeroShares());
        LinkedList.List storage thawRequestList = _getThawRequestList(
            _requestType,
            _serviceProvider,
            _verifier,
            _owner
        );
        require(thawRequestList.count < MAX_THAW_REQUESTS, HorizonStakingTooManyThawRequests());

        bytes32 thawRequestId = keccak256(abi.encodePacked(_serviceProvider, _verifier, _owner, thawRequestList.nonce));
        ThawRequest storage thawRequest = _getThawRequest(_requestType, thawRequestId);
        thawRequest.shares = _shares;
        thawRequest.thawingUntil = _thawingUntil;
        thawRequest.nextRequest = bytes32(0);
        thawRequest.thawingNonce = _thawingNonce;

        if (thawRequestList.count != 0) _getThawRequest(_requestType, thawRequestList.tail).nextRequest = thawRequestId;
        thawRequestList.addTail(thawRequestId);

        emit ThawRequestCreated(
            _requestType,
            _serviceProvider,
            _verifier,
            _owner,
            _shares,
            _thawingUntil,
            thawRequestId,
            _thawingNonce
        );
        return thawRequestId;
    }

    /**
     * @notice Traverses a thaw request list and fulfills expired thaw requests.
     * @dev Note that the list is traversed by creation date not by thawing until date. Traversing will stop
     * when the first thaw request that is not yet expired is found even if later thaw requests have expired. This
     * could happen for example when the thawing period is shortened.
     * @param _params The parameters for fulfilling thaw requests
     * @return The amount of thawed tokens
     * @return The amount of tokens still thawing
     * @return The amount of shares still thawing
     */
    function _fulfillThawRequests(
        FulfillThawRequestsParams memory _params
    ) private returns (uint256, uint256, uint256) {
        LinkedList.List storage thawRequestList = _getThawRequestList(
            _params.requestType,
            _params.serviceProvider,
            _params.verifier,
            _params.owner
        );
        require(thawRequestList.count > 0, HorizonStakingNothingThawing());

        TraverseThawRequestsResults memory results = _traverseThawRequests(_params, thawRequestList);

        emit ThawRequestsFulfilled(
            _params.requestType,
            _params.serviceProvider,
            _params.verifier,
            _params.owner,
            results.requestsFulfilled,
            results.tokensThawed
        );

        return (results.tokensThawed, results.tokensThawing, results.sharesThawing);
    }

    /**
     * @notice Traverses a thaw request list and fulfills expired thaw requests.
     * @param _params The parameters for fulfilling thaw requests
     * @param _thawRequestList The list of thaw requests to traverse
     * @return The results of the traversal
     */
    function _traverseThawRequests(
        FulfillThawRequestsParams memory _params,
        LinkedList.List storage _thawRequestList
    ) private returns (TraverseThawRequestsResults memory) {
        function(bytes32) view returns (bytes32) getNextItem = _getNextThawRequest(_params.requestType);
        function(bytes32) deleteItem = _getDeleteThawRequest(_params.requestType);

        bytes memory acc = abi.encode(
            _params.requestType,
            uint256(0),
            _params.tokensThawing,
            _params.sharesThawing,
            _params.thawingNonce
        );
        (uint256 thawRequestsFulfilled, bytes memory data) = _thawRequestList.traverse(
            getNextItem,
            _fulfillThawRequest,
            deleteItem,
            acc,
            _params.nThawRequests
        );

        (, uint256 tokensThawed, uint256 tokensThawing, uint256 sharesThawing) = abi.decode(
            data,
            (ThawRequestType, uint256, uint256, uint256)
        );

        return
            TraverseThawRequestsResults({
                requestsFulfilled: thawRequestsFulfilled,
                tokensThawed: tokensThawed,
                tokensThawing: tokensThawing,
                sharesThawing: sharesThawing
            });
    }

    /**
     * @notice Fulfills a thaw request.
     * @dev This function is used as a callback in the thaw requests linked list traversal.
     * @param _thawRequestId The ID of the current thaw request
     * @param _acc The accumulator data for the thaw requests being fulfilled
     * @return Whether the thaw request is still thawing, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function _fulfillThawRequest(bytes32 _thawRequestId, bytes memory _acc) private returns (bool, bytes memory) {
        // decode
        (
            ThawRequestType requestType,
            uint256 tokensThawed,
            uint256 tokensThawing,
            uint256 sharesThawing,
            uint256 thawingNonce
        ) = abi.decode(_acc, (ThawRequestType, uint256, uint256, uint256, uint256));

        ThawRequest storage thawRequest = _getThawRequest(requestType, _thawRequestId);

        // early exit
        if (thawRequest.thawingUntil > block.timestamp) {
            return (true, LinkedList.NULL_BYTES);
        }

        // process - only fulfill thaw requests for the current valid nonce
        uint256 tokens = 0;
        bool validThawRequest = thawRequest.thawingNonce == thawingNonce;
        if (validThawRequest) {
            // sharesThawing cannot be zero if there is a valid thaw request so the next division is safe
            tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
            tokensThawing = tokensThawing - tokens;
            sharesThawing = sharesThawing - thawRequest.shares;
            tokensThawed = tokensThawed + tokens;
        }
        emit ThawRequestFulfilled(
            requestType,
            _thawRequestId,
            tokens,
            thawRequest.shares,
            thawRequest.thawingUntil,
            validThawRequest
        );

        // encode
        _acc = abi.encode(requestType, tokensThawed, tokensThawing, sharesThawing, thawingNonce);
        return (false, _acc);
    }

    /**
     * @notice Deletes a thaw request for a provision.
     * @param _thawRequestId The ID of the thaw request to delete.
     */
    function _deleteProvisionThawRequest(bytes32 _thawRequestId) private {
        delete _thawRequests[ThawRequestType.Provision][_thawRequestId];
    }

    /**
     * @notice Deletes a thaw request for a delegation.
     * @param _thawRequestId The ID of the thaw request to delete.
     */
    function _deleteDelegationThawRequest(bytes32 _thawRequestId) private {
        delete _thawRequests[ThawRequestType.Delegation][_thawRequestId];
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the operator settings are stored in the legacy mapping.
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function _setOperator(address _verifier, address _operator, bool _allowed) private {
        require(_operator != msg.sender, HorizonStakingCallerIsServiceProvider());
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            _legacyOperatorAuth[msg.sender][_operator] = _allowed;
        } else {
            _operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        }
        emit OperatorSet(msg.sender, _verifier, _operator, _allowed);
    }

    /**
     * @notice Check if an operator is authorized for the caller on a specific verifier / data service.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the operator settings are stored in the legacy mapping.
     * @param _serviceProvider The service provider on behalf of whom they're claiming to act
     * @param _verifier The verifier / data service on which they're claiming to act
     * @param _operator The address to check for auth
     * @return Whether the operator is authorized or not
     */
    function _isAuthorized(address _serviceProvider, address _verifier, address _operator) private view returns (bool) {
        if (_operator == _serviceProvider) {
            return true;
        }
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return _legacyOperatorAuth[_serviceProvider][_operator];
        } else {
            return _operatorAuth[_serviceProvider][_verifier][_operator];
        }
    }

    /**
     * @notice Determines the correct callback function for `deleteItem` based on the request type.
     * @param _requestType The type of thaw request (Provision or Delegation).
     * @return A function pointer to the appropriate `deleteItem` callback.
     */
    function _getDeleteThawRequest(ThawRequestType _requestType) private pure returns (function(bytes32)) {
        if (_requestType == ThawRequestType.Provision) {
            return _deleteProvisionThawRequest;
        } else if (_requestType == ThawRequestType.Delegation) {
            return _deleteDelegationThawRequest;
        } else {
            revert HorizonStakingInvalidThawRequestType();
        }
    }
}
