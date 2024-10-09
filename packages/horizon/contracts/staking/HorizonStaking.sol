// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

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

    /// @dev Fixed point precision
    uint256 private constant FIXED_POINT_PRECISION = 1e18;

    /// @dev Maximum number of simultaneous stake thaw requests (per provision) or undelegations (per delegation)
    uint256 private constant MAX_THAW_REQUESTS = 100;

    /// @dev Address of the staking extension contract
    address private immutable STAKING_EXTENSION_ADDRESS;

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

    /**
     * @notice See {IHorizonStakingMain-stake}.
     */
    function stake(uint256 tokens) external override notPaused {
        _stakeTo(msg.sender, tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-stakeTo}.
     */
    function stakeTo(address serviceProvider, uint256 tokens) external override notPaused {
        _stakeTo(serviceProvider, tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-stakeToProvision}.
     */
    function stakeToProvision(address serviceProvider, address verifier, uint256 tokens) external override notPaused {
        _stakeTo(serviceProvider, tokens);
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-unstake}.
     */
    function unstake(uint256 tokens) external override notPaused {
        _unstake(tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-withdraw}.
     */
    function withdraw() external override notPaused {
        _withdraw(msg.sender);
    }

    /*
     * PROVISIONS
     */

    /**
     * @notice See {IHorizonStakingMain-provision}.
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
     * @notice See {IHorizonStakingMain-addToProvision}.
     */
    function addToProvision(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        _addToProvision(serviceProvider, verifier, tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-thaw}.
     */
    function thaw(
        address serviceProvider,
        address verifier,
        uint256 tokens
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) returns (bytes32) {
        return _thaw(serviceProvider, verifier, tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-deprovision}.
     */
    function deprovision(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) external override onlyAuthorized(serviceProvider, verifier) notPaused {
        _deprovision(serviceProvider, verifier, nThawRequests);
    }

    /**
     * @notice See {IHorizonStakingMain-reprovision}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-setProvisionParameters}.
     */
    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 newMaxVerifierCut,
        uint64 newThawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        require(PPMMath.isValidPPM(newMaxVerifierCut), HorizonStakingInvalidMaxVerifierCut(newMaxVerifierCut));
        require(
            newThawingPeriod <= _maxThawingPeriod,
            HorizonStakingInvalidThawingPeriod(newThawingPeriod, _maxThawingPeriod)
        );
        Provision storage prov = _provisions[serviceProvider][verifier];
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(serviceProvider, verifier));

        if ((prov.maxVerifierCutPending != newMaxVerifierCut) || (prov.thawingPeriodPending != newThawingPeriod)) {
            prov.maxVerifierCutPending = newMaxVerifierCut;
            prov.thawingPeriodPending = newThawingPeriod;
            emit ProvisionParametersStaged(serviceProvider, verifier, newMaxVerifierCut, newThawingPeriod);
        }
    }

    /**
     * @notice See {IHorizonStakingMain-acceptProvisionParameters}.
     */
    function acceptProvisionParameters(address serviceProvider) external override notPaused {
        address verifier = msg.sender;
        Provision storage prov = _provisions[serviceProvider][verifier];
        if ((prov.maxVerifierCutPending != prov.maxVerifierCut) || (prov.thawingPeriodPending != prov.thawingPeriod)) {
            prov.maxVerifierCut = prov.maxVerifierCutPending;
            prov.thawingPeriod = prov.thawingPeriodPending;
            emit ProvisionParametersSet(serviceProvider, verifier, prov.maxVerifierCut, prov.thawingPeriod);
        }
    }

    /*
     * DELEGATION
     */

    /**
     * @notice See {IHorizonStakingMain-delegate}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-addToDelegationPool}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-undelegate}.
     */
    function undelegate(
        address serviceProvider,
        address verifier,
        uint256 shares
    ) external override notPaused returns (bytes32) {
        return _undelegate(serviceProvider, verifier, shares, msg.sender);
    }

    /**
     * @notice See {IHorizonStakingMain-undelegate}.
     */
    function undelegate(
        address serviceProvider,
        address verifier,
        uint256 shares,
        address beneficiary
    ) external override notPaused returns (bytes32) {
        require(beneficiary != address(0), HorizonStakingInvalidBeneficiaryZeroAddress());
        return _undelegate(serviceProvider, verifier, shares, beneficiary);
    }

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
     */
    function withdrawDelegated(
        address serviceProvider,
        address verifier,
        uint256 nThawRequests
    ) external override notPaused {
        _withdrawDelegated(serviceProvider, verifier, address(0), address(0), 0, nThawRequests);
    }

    /**
     * @notice See {IHorizonStakingMain-redelegate}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-setDelegationFeeCut}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-delegate}.
     */
    function delegate(address serviceProvider, uint256 tokens) external override notPaused {
        require(tokens != 0, HorizonStakingInvalidZeroTokens());
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, tokens, 0);
    }

    /**
     * @notice See {IHorizonStakingMain-undelegate}.
     */
    function undelegate(address serviceProvider, uint256 shares) external override notPaused {
        _undelegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, shares, msg.sender);
    }

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
     */
    function withdrawDelegated(address serviceProvider, address newServiceProvider) external override notPaused {
        _withdrawDelegated(
            serviceProvider,
            SUBGRAPH_DATA_SERVICE_ADDRESS,
            newServiceProvider,
            SUBGRAPH_DATA_SERVICE_ADDRESS,
            0,
            0
        );
    }

    /*
     * SLASHING
     */

    /**
     * @notice See {IHorizonStakingMain-slash}.
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
        require(tokensProvisionTotal != 0, HorizonStakingInsufficientTokens(tokensProvisionTotal, tokens));

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

            // Provision accounting
            // TODO check for rounding issues
            uint256 provisionFractionSlashed = (providerTokensSlashed * FIXED_POINT_PRECISION) / prov.tokens;
            prov.tokensThawing =
                (prov.tokensThawing * (FIXED_POINT_PRECISION - provisionFractionSlashed)) /
                (FIXED_POINT_PRECISION);
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

                // Delegation pool accounting
                uint256 delegationFractionSlashed = (tokensToSlash * FIXED_POINT_PRECISION) / pool.tokens;
                pool.tokens = pool.tokens - tokensToSlash;
                pool.tokensThawing =
                    (pool.tokensThawing * (FIXED_POINT_PRECISION - delegationFractionSlashed)) /
                    FIXED_POINT_PRECISION;

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

    /**
     * @notice See {IHorizonStakingMain-provisionLocked}.
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

    /**
     * @notice See {IHorizonStakingMain-setOperatorLocked}.
     */
    function setOperatorLocked(address verifier, address operator, bool allowed) external override notPaused {
        require(_allowedLockedVerifiers[verifier], HorizonStakingVerifierNotAllowed(verifier));
        _setOperator(verifier, operator, allowed);
    }

    /*
     * GOVERNANCE
     */

    /**
     * @notice See {IHorizonStakingMain-setAllowedLockedVerifier}.
     */
    function setAllowedLockedVerifier(address verifier, bool allowed) external override onlyGovernor {
        _allowedLockedVerifiers[verifier] = allowed;
        emit AllowedLockedVerifierSet(verifier, allowed);
    }

    /**
     * @notice See {IHorizonStakingMain-setDelegationSlashingEnabled}.
     */
    function setDelegationSlashingEnabled() external override onlyGovernor {
        _delegationSlashingEnabled = true;
        emit DelegationSlashingEnabled(_delegationSlashingEnabled);
    }

    /**
     * @notice See {IHorizonStakingMain-clearThawingPeriod}.
     */
    function clearThawingPeriod() external override onlyGovernor {
        __DEPRECATED_thawingPeriod = 0;
        emit ThawingPeriodCleared();
    }

    /**
     * @notice See {IHorizonStakingMain-setMaxThawingPeriod}.
     */
    function setMaxThawingPeriod(uint64 maxThawingPeriod) external override onlyGovernor {
        _maxThawingPeriod = maxThawingPeriod;
        emit MaxThawingPeriodSet(_maxThawingPeriod);
    }

    /*
     * OPERATOR
     */

    /**
     * @notice See {IHorizonStakingMain-setOperator}.
     */
    function setOperator(address verifier, address operator, bool allowed) external override notPaused {
        _setOperator(verifier, operator, allowed);
    }

    /**
     * @notice See {IHorizonStakingMain-isAuthorized}.
     */
    function isAuthorized(
        address serviceProvider,
        address verifier,
        address operator
    ) external view override returns (bool) {
        return _isAuthorized(serviceProvider, verifier, operator);
    }

    /*
     * PRIVATE FUNCTIONS
     */

    /**
     * @notice See {IHorizonStakingMain-stakeTo}.
     */
    function _stakeTo(address _serviceProvider, uint256 _tokens) private {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());

        // Transfer tokens to stake from caller to this contract
        _graphToken().pullTokens(msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_serviceProvider, _tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-unstake}.
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
            emit StakeWithdrawn(serviceProvider, _tokens);
        } else {
            // Before locking more tokens, withdraw any unlocked ones if possible
            if (sp.__DEPRECATED_tokensLocked != 0 && block.number >= sp.__DEPRECATED_tokensLockedUntil) {
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
     * @notice See {IHorizonStakingMain-withdraw}.
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

        emit StakeWithdrawn(_serviceProvider, tokensToWithdraw);
    }

    /**
     * @notice See {IHorizonStakingMain-createProvision}.
     */
    function _createProvision(
        address _serviceProvider,
        uint256 _tokens,
        address _verifier,
        uint32 _maxVerifierCut,
        uint64 _thawingPeriod
    ) private {
        require(_tokens > 0, HorizonStakingInvalidZeroTokens());
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
            thawingNonce: 0
        });

        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        sp.tokensProvisioned = sp.tokensProvisioned + _tokens;

        emit ProvisionCreated(_serviceProvider, _verifier, _tokens, _maxVerifierCut, _thawingPeriod);
    }

    /**
     * @notice See {IHorizonStakingMain-addToProvision}.
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
     * @notice See {IHorizonStakingMain-thaw}.
     * @dev We use a thawing pool to keep track of tokens thawing for multiple thaw requests.
     * If due to slashing the thawing pool loses all of its tokens, the pool is reset and all pending thaw
     * requests are invalidated.
     */
    function _thaw(address _serviceProvider, address _verifier, uint256 _tokens) private returns (bytes32) {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        uint256 tokensAvailable = _getProviderTokensAvailable(_serviceProvider, _verifier);
        require(tokensAvailable >= _tokens, HorizonStakingInsufficientTokens(tokensAvailable, _tokens));

        Provision storage prov = _provisions[_serviceProvider][_verifier];

        // Calculate shares to issue
        // Thawing pool is reset/initialized when the pool is empty: prov.tokensThawing == 0
        uint256 thawingShares = prov.tokensThawing == 0
            ? _tokens
            : ((prov.sharesThawing * _tokens) / prov.tokensThawing);
        uint64 thawingUntil = uint64(block.timestamp + uint256(prov.thawingPeriod));

        prov.sharesThawing = prov.sharesThawing + thawingShares;
        prov.tokensThawing = prov.tokensThawing + _tokens;

        bytes32 thawRequestId = _createThawRequest(
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
     * @notice See {IHorizonStakingMain-deprovision}.
     */
    function _deprovision(
        address _serviceProvider,
        address _verifier,
        uint256 _nThawRequests
    ) private returns (uint256 tokensThawed) {
        Provision storage prov = _provisions[_serviceProvider][_verifier];

        uint256 tokensThawed_ = 0;
        uint256 sharesThawing = prov.sharesThawing;
        uint256 tokensThawing = prov.tokensThawing;
        (tokensThawed_, tokensThawing, sharesThawing) = _fulfillThawRequests(
            _serviceProvider,
            _verifier,
            _serviceProvider,
            tokensThawing,
            sharesThawing,
            _nThawRequests,
            prov.thawingNonce
        );

        prov.tokens = prov.tokens - tokensThawed_;
        prov.sharesThawing = sharesThawing;
        prov.tokensThawing = tokensThawing;
        _serviceProviders[_serviceProvider].tokensProvisioned -= tokensThawed_;

        emit TokensDeprovisioned(_serviceProvider, _verifier, tokensThawed_);
        return tokensThawed_;
    }

    /**
     * @notice See {IHorizonStakingMain-delegate}.
     * @dev Note that this function does not pull the delegated tokens from the caller. It expects that to
     * have been done before calling this function.
     */
    function _delegate(address _serviceProvider, address _verifier, uint256 _tokens, uint256 _minSharesOut) private {
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

        emit TokensDelegated(_serviceProvider, _verifier, msg.sender, _tokens);
    }

    /**
     * @notice See {IHorizonStakingMain-undelegate}.
     * @dev To allow delegation to be slashable even while thawing without breaking accounting
     * the delegation pool shares are burned and replaced with thawing pool shares.
     * @dev Note that due to slashing the delegation pool can enter an invalid state if all it's tokens are slashed.
     * An invalid pool can only be recovered by adding back tokens into the pool with {IHorizonStakingMain-addToDelegationPool}.
     * Any time the delegation pool is invalidated, the thawing pool is also reset and any pending undelegate requests get
     * invalidated.
     * Note that delegation that is caught thawing when the pool is invalidated will be completely lost! However delegation shares
     * that were not thawing will be preserved.
     */
    function _undelegate(
        address _serviceProvider,
        address _verifier,
        uint256 _shares,
        address beneficiary
    ) private returns (bytes32) {
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
        uint256 thawingShares = pool.tokensThawing == 0 ? tokens : ((tokens * pool.sharesThawing) / pool.tokensThawing);
        uint64 thawingUntil = uint64(block.timestamp + uint256(_provisions[_serviceProvider][_verifier].thawingPeriod));

        pool.tokensThawing = pool.tokensThawing + tokens;
        pool.sharesThawing = pool.sharesThawing + thawingShares;

        pool.shares = pool.shares - _shares;
        delegation.shares = delegation.shares - _shares;

        bytes32 thawRequestId = _createThawRequest(
            _serviceProvider,
            _verifier,
            beneficiary,
            thawingShares,
            thawingUntil,
            pool.thawingNonce
        );

        emit TokensUndelegated(_serviceProvider, _verifier, msg.sender, tokens);
        return thawRequestId;
    }

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
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
        (tokensThawed, tokensThawing, sharesThawing) = _fulfillThawRequests(
            _serviceProvider,
            _verifier,
            msg.sender,
            tokensThawing,
            sharesThawing,
            _nThawRequests,
            pool.thawingNonce
        );

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
            }
        }

        emit DelegatedTokensWithdrawn(_serviceProvider, _verifier, msg.sender, tokensThawed);
    }

    /**
     * @notice Creates a thaw request.
     * Allows creating thaw requests up to a maximum of `MAX_THAW_REQUESTS` per owner.
     * Thaw requests are stored in a linked list per owner (and service provider, verifier) to allow for efficient
     * processing.
     * @dev Emits a {ThawRequestCreated} event.
     * @param _serviceProvider The address of the service provider
     * @param _verifier The address of the verifier
     * @param _owner The address of the owner of the thaw request
     * @param _shares The number of shares to thaw
     * @param _thawingUntil The timestamp until which the shares are thawing
     * @param _thawingNonce Owner's validity nonce for the thaw request
     * @return The ID of the thaw request
     */
    function _createThawRequest(
        address _serviceProvider,
        address _verifier,
        address _owner,
        uint256 _shares,
        uint64 _thawingUntil,
        uint256 _thawingNonce
    ) private returns (bytes32) {
        LinkedList.List storage thawRequestList = _thawRequestLists[_serviceProvider][_verifier][_owner];
        require(thawRequestList.count < MAX_THAW_REQUESTS, HorizonStakingTooManyThawRequests());

        bytes32 thawRequestId = keccak256(abi.encodePacked(_serviceProvider, _verifier, _owner, thawRequestList.nonce));
        _thawRequests[thawRequestId] = ThawRequest({
            shares: _shares,
            thawingUntil: _thawingUntil,
            next: bytes32(0),
            thawingNonce: _thawingNonce
        });

        if (thawRequestList.count != 0) _thawRequests[thawRequestList.tail].next = thawRequestId;
        thawRequestList.addTail(thawRequestId);

        emit ThawRequestCreated(_serviceProvider, _verifier, _owner, _shares, _thawingUntil, thawRequestId);
        return thawRequestId;
    }

    /**
     * @notice Traverses a thaw request list and fulfills expired thaw requests.
     * @dev Emits a {ThawRequestsFulfilled} event and a {ThawRequestFulfilled} event for each thaw request fulfilled.
     * @param _serviceProvider The address of the service provider
     * @param _verifier The address of the verifier
     * @param _owner The address of the owner of the thaw request
     * @param _tokensThawing The current amount of tokens already thawing
     * @param _sharesThawing The current amount of shares already thawing
     * @param _nThawRequests The number of thaw requests to fulfill. If set to 0, all thaw requests are fulfilled.
     * @param _thawingNonce The current valid thawing nonce. Any thaw request with a different nonce is invalid and should be ignored.
     * @return The amount of thawed tokens
     * @return The amount of tokens still thawing
     * @return The amount of shares still thawing
     */
    function _fulfillThawRequests(
        address _serviceProvider,
        address _verifier,
        address _owner,
        uint256 _tokensThawing,
        uint256 _sharesThawing,
        uint256 _nThawRequests,
        uint256 _thawingNonce
    ) private returns (uint256, uint256, uint256) {
        LinkedList.List storage thawRequestList = _thawRequestLists[_serviceProvider][_verifier][_owner];
        require(thawRequestList.count > 0, HorizonStakingNothingThawing());

        uint256 tokensThawed = 0;
        (uint256 thawRequestsFulfilled, bytes memory data) = thawRequestList.traverse(
            _getNextThawRequest,
            _fulfillThawRequest,
            _deleteThawRequest,
            abi.encode(tokensThawed, _tokensThawing, _sharesThawing, _thawingNonce),
            _nThawRequests
        );

        (tokensThawed, _tokensThawing, _sharesThawing) = abi.decode(data, (uint256, uint256, uint256));
        emit ThawRequestsFulfilled(_serviceProvider, _verifier, _owner, thawRequestsFulfilled, tokensThawed);
        return (tokensThawed, _tokensThawing, _sharesThawing);
    }

    /**
     * @notice Fulfills a thaw request.
     * @dev This function is used as a callback in the thaw requests linked list traversal.
     *
     * Emits a {ThawRequestFulfilled} event.
     *
     * @param _thawRequestId The ID of the current thaw request
     * @param _acc The accumulator data for the thaw requests being fulfilled
     * @return Whether the thaw request is still thawing, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function _fulfillThawRequest(bytes32 _thawRequestId, bytes memory _acc) private returns (bool, bytes memory) {
        ThawRequest storage thawRequest = _thawRequests[_thawRequestId];

        // early exit
        if (thawRequest.thawingUntil > block.timestamp) {
            return (true, LinkedList.NULL_BYTES);
        }

        // decode
        (uint256 tokensThawed, uint256 tokensThawing, uint256 sharesThawing, uint256 thawingNonce) = abi.decode(
            _acc,
            (uint256, uint256, uint256, uint256)
        );

        // process - only fulfill thaw requests for the current valid nonce
        uint256 tokens = 0;
        bool validThawRequest = thawRequest.thawingNonce == thawingNonce;
        if (validThawRequest) {
            tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
            tokensThawing = tokensThawing - tokens;
            sharesThawing = sharesThawing - thawRequest.shares;
            tokensThawed = tokensThawed + tokens;
        }
        emit ThawRequestFulfilled(
            _thawRequestId,
            tokens,
            thawRequest.shares,
            thawRequest.thawingUntil,
            validThawRequest
        );

        // encode
        _acc = abi.encode(tokensThawed, tokensThawing, sharesThawing, thawingNonce);
        return (false, _acc);
    }

    /**
     * @notice Deletes a ThawRequest.
     * @dev This function is used as a callback in the thaw requests linked list traversal.
     * @param _thawRequestId The ID of the thaw request to delete
     */
    function _deleteThawRequest(bytes32 _thawRequestId) private {
        delete _thawRequests[_thawRequestId];
    }

    /**
     * @notice See {IHorizonStakingMain-setOperator}.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the operator settings are stored in the legacy mapping.
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
     * @notice See {IHorizonStakingMain-isAuthorized}.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the operator settings are stored in the legacy mapping.
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
}
