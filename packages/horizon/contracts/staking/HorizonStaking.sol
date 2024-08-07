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
 * @notice The {HorizonStaking} contract allows service providers to stake and provision tokens to verifiers to be used
 * as economic security for a service. It also allows delegators to delegate towards a service provider provision.
 * @dev Implements the {IHorizonStakingMain} interface.
 * @dev This is the main Staking contract in The Graph protocol after the Horizon upgrade.
 * It is designed to be deployed as an upgrade to the L2Staking contract from the legacy contracts package.
 * @dev It uses a {HorizonStakingExtension} contract to implement the full {IHorizonStaking} interface through delegatecalls.
 * This is due to the contract size limit on Arbitrum (24kB). The extension contract implements functionality to support
 * the legacy staking functions and the transfer tools. Both can be eventually removed without affecting the main
 * staking contract.
 */
contract HorizonStaking is HorizonStakingBase, IHorizonStakingMain {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;
    using LinkedList for LinkedList.List;

    /// @dev Maximum value that can be set as the maxVerifierCut in a provision.
    /// It is equivalent to 100% in parts-per-million
    uint32 private constant MAX_MAX_VERIFIER_CUT = uint32(PPMMath.MAX_PPM);

    /// @dev Fixed point precision
    uint256 private constant FIXED_POINT_PRECISION = 1e18;

    /// @dev Maximum number of simultaneous stake thaw requests (per provision) or undelegations (per delegation)
    uint256 private constant MAX_THAW_REQUESTS = 100;

    /// @dev Minimum amount of delegation to prevent rounding attacks.
    /// TODO: remove this after L2 transfer tool for delegation is removed
    /// (delegation on L2 has its own slippage protection)
    uint256 private constant MIN_DELEGATION = 1e18;

    /// @dev Address of the staking extension contract
    address private immutable STAKING_EXTENSION_ADDRESS;

    /**
     * @notice Checks that the caller is authorized to operate over a provision.
     * @param serviceProvider The address of the service provider.
     * @param verifier The address of the verifier.
     */
    modifier onlyAuthorized(address serviceProvider, address verifier) {
        require(
            _isAuthorized(msg.sender, serviceProvider, verifier),
            HorizonStakingNotAuthorized(msg.sender, serviceProvider, verifier)
        );
        _;
    }

    /**
     * @dev The staking contract is upgradeable however we stil use the constructor to set
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
        _withdraw(msg.sender, true);
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

    /**
     * @notice See {IHorizonStakingMain-setProvisionParameters}.
     */
    function setProvisionParameters(
        address serviceProvider,
        address verifier,
        uint32 maxVerifierCut,
        uint64 thawingPeriod
    ) external override notPaused onlyAuthorized(serviceProvider, verifier) {
        Provision storage prov = _provisions[serviceProvider][verifier];
        require(prov.createdAt != 0, HorizonStakingInvalidProvision(serviceProvider, verifier));

        if ((prov.maxVerifierCutPending != maxVerifierCut) || (prov.thawingPeriodPending != thawingPeriod)) {
            prov.maxVerifierCutPending = maxVerifierCut;
            prov.thawingPeriodPending = thawingPeriod;
            emit ProvisionParametersStaged(serviceProvider, verifier, maxVerifierCut, thawingPeriod);
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
        require(msg.sender == verifier || msg.sender == address(_graphPayments()), HorizonStakingInvalidDelegationPoolSender(msg.sender));
        _graphToken().pullTokens(msg.sender, tokens);
        DelegationPoolInternal storage pool = _getDelegationPool(serviceProvider, verifier);
        pool.tokens = pool.tokens + tokens;
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
        return _undelegate(serviceProvider, verifier, shares);
    }

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
     */
    function withdrawDelegated(
        address serviceProvider,
        address verifier,
        address newServiceProvider,
        uint256 minSharesForNewProvider,
        uint256 nThawRequests
    ) external override notPaused {
        _withdrawDelegated(serviceProvider, verifier, newServiceProvider, minSharesForNewProvider, nThawRequests);
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
        _delegationFeeCut[serviceProvider][verifier][paymentType] = feeCut;
        emit DelegationFeeCutSet(serviceProvider, verifier, paymentType, feeCut);
    }

    /**
     * @notice See {IHorizonStakingMain-delegate}.
     */
    function delegate(address serviceProvider, uint256 tokens) external override notPaused {
        _graphToken().pullTokens(msg.sender, tokens);
        _delegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, tokens, 0);
    }

    /**
     * @notice See {IHorizonStakingMain-undelegate}.
     */
    function undelegate(address serviceProvider, uint256 shares) external override notPaused {
        _undelegate(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, shares);
    }

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
     */
    function withdrawDelegated(address serviceProvider, address newServiceProvider) external override notPaused {
        _withdrawDelegated(serviceProvider, SUBGRAPH_DATA_SERVICE_ADDRESS, newServiceProvider, 0, 0);
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
        require(tokensProvisionTotal >= tokens, HorizonStakingInsufficientTokens(prov.tokens, tokens));

        uint256 tokensToSlash = tokens;
        uint256 providerTokensSlashed = MathUtils.min(prov.tokens, tokensToSlash);
        if (providerTokensSlashed > 0) {
            uint256 maxVerifierTokens = prov.tokens.mulPPM(prov.maxVerifierCut);
            require(
                maxVerifierTokens >= tokensVerifier,
                HorizonStakingTooManyTokens(tokensVerifier, maxVerifierTokens)
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
    function setOperatorLocked(address operator, address verifier, bool allowed) external override notPaused {
        require(_allowedLockedVerifiers[verifier], HorizonStakingVerifierNotAllowed(verifier));
        _setOperator(operator, verifier, allowed);
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
    function setDelegationSlashingEnabled(bool enabled) external override onlyGovernor {
        _delegationSlashingEnabled = enabled;
        emit DelegationSlashingEnabled(enabled);
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
    function setOperator(address operator, address verifier, bool allowed) external override notPaused {
        _setOperator(operator, verifier, allowed);
    }

    /**
     * @notice See {IHorizonStakingMain-isAuthorized}.
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
        // Check that the service provider's stake minus the tokens to unstake is sufficient
        // to cover existing allocations
        // TODO this is only needed until legacy allocations are closed,
        // so we should remove it after the transition period
        uint256 remainingTokens = stakedTokens - _tokens;
        require(
            remainingTokens >= sp.__DEPRECATED_tokensAllocated,
            HorizonStakingInsufficientStakeForLegacyAllocations(remainingTokens, sp.__DEPRECATED_tokensAllocated)
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
                _withdraw(serviceProvider, false);
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
     * @param _revertIfThawing If true, the function will revert if the tokens are still thawing
     */
    function _withdraw(address _serviceProvider, bool _revertIfThawing) private {
        // Get tokens available for withdraw and update balance
        ServiceProviderInternal storage sp = _serviceProviders[_serviceProvider];
        uint256 tokensToWithdraw = sp.__DEPRECATED_tokensLocked;
        require(tokensToWithdraw != 0, HorizonStakingInvalidZeroTokens());

        if (_revertIfThawing) {
            require(
                block.timestamp >= sp.__DEPRECATED_tokensLockedUntil,
                HorizonStakingStillThawing(sp.__DEPRECATED_tokensLockedUntil)
            );
        } else {
            return;
        }

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
        require(
            _maxVerifierCut <= MAX_MAX_VERIFIER_CUT,
            HorizonStakingInvalidMaxVerifierCut(_maxVerifierCut, MAX_MAX_VERIFIER_CUT)
        );
        require(
            _thawingPeriod <= _maxThawingPeriod,
            HorizonStakingInvalidThawingPeriod(_thawingPeriod, _maxThawingPeriod)
        );
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
            thawingPeriodPending: _thawingPeriod
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
     */
    function _thaw(address _serviceProvider, address _verifier, uint256 _tokens) private returns (bytes32) {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());
        uint256 tokensAvailable = _getProviderTokensAvailable(_serviceProvider, _verifier);
        require(tokensAvailable >= _tokens, HorizonStakingInsufficientTokens(tokensAvailable, _tokens));

        Provision storage prov = _provisions[_serviceProvider][_verifier];
        uint256 thawingShares = prov.sharesThawing == 0 ? _tokens : (prov.sharesThawing * _tokens) / prov.tokensThawing;
        uint64 thawingUntil = uint64(block.timestamp + uint256(prov.thawingPeriod));

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

    /**
     * @notice See {IHorizonStakingMain-deprovision}.
     */
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

    /**
     * @notice See {IHorizonStakingMain-delegate}.
     * @dev Note that this function does not pull the delegated tokens from the caller. It expects that to
     * have been done before calling this function.
     */
    function _delegate(address _serviceProvider, address _verifier, uint256 _tokens, uint256 _minSharesOut) private {
        require(_tokens != 0, HorizonStakingInvalidZeroTokens());

        // TODO: remove this after L2 transfer tool for delegation is removed
        require(_tokens >= MIN_DELEGATION, HorizonStakingInsufficientTokens(_tokens, MIN_DELEGATION));
        require(
            _provisions[_serviceProvider][_verifier].createdAt != 0,
            HorizonStakingInvalidProvision(_serviceProvider, _verifier)
        );

        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? _tokens : ((_tokens * pool.shares) / (pool.tokens - pool.tokensThawing));
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
     */
    function _undelegate(address _serviceProvider, address _verifier, uint256 _shares) private returns (bytes32) {
        require(_shares > 0, HorizonStakingInvalidZeroShares());
        DelegationPoolInternal storage pool = _getDelegationPool(_serviceProvider, _verifier);
        DelegationInternal storage delegation = pool.delegators[msg.sender];
        require(delegation.shares >= _shares, HorizonStakingInsufficientShares(delegation.shares, _shares));

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

    /**
     * @notice See {IHorizonStakingMain-withdrawDelegated}.
     */
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

        if (tokensThawed != 0) {
            if (_newServiceProvider != address(0)) {
                _delegate(_newServiceProvider, _verifier, tokensThawed, _minSharesForNewProvider);
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
     * @return The ID of the thaw request
     */
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

    /**
     * @notice Fulfills a thaw request.
     * @dev This function is used as a callback in the thaw requests linked list traversal.
     *
     * Emits a {ThawRequestFulfilled} event.
     *
     * @param _thawRequestId The ID of the current thaw request
     * @param _acc The accumulator data for the thaw requests being fulfilled
     * @return Wether the thaw request is still thawing, indicating that the traversal should continue or stop.
     * @return The updated accumulator data
     */
    function _fulfillThawRequest(bytes32 _thawRequestId, bytes memory _acc) private returns (bool, bytes memory) {
        ThawRequest storage thawRequest = _thawRequests[_thawRequestId];

        // early exit
        if (thawRequest.thawingUntil > block.timestamp) {
            return (true, LinkedList.NULL_BYTES);
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
    function _setOperator(address _operator, address _verifier, bool _allowed) private {
        require(_operator != msg.sender, HorizonStakingCallerIsServiceProvider());
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            _legacyOperatorAuth[msg.sender][_operator] = _allowed;
        } else {
            _operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        }
        emit OperatorSet(msg.sender, _operator, _verifier, _allowed);
    }

    /**
     * @notice See {IHorizonStakingMain-isAuthorized}.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the operator settings are stored in the legacy mapping.
     */
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
