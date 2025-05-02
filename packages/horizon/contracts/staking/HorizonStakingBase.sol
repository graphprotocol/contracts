// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IHorizonStakingTypes } from "../interfaces/internal/IHorizonStakingTypes.sol";
import { IHorizonStakingBase } from "../interfaces/internal/IHorizonStakingBase.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";

import { MathUtils } from "../libraries/MathUtils.sol";
import { LinkedList } from "../libraries/LinkedList.sol";

import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import { Managed } from "./utilities/Managed.sol";
import { HorizonStakingV1Storage } from "./HorizonStakingStorage.sol";

/**
 * @title HorizonStakingBase contract
 * @notice This contract is the base staking contract implementing storage getters for both internal
 * and external use.
 * @dev Implementation of the {IHorizonStakingBase} interface.
 * @dev It's meant to be inherited by the {HorizonStaking} and {HorizonStakingExtension}
 * contracts so some internal functions are also included here.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract HorizonStakingBase is
    Multicall,
    Managed,
    HorizonStakingV1Storage,
    GraphUpgradeable,
    IHorizonStakingTypes,
    IHorizonStakingBase
{
    using LinkedList for LinkedList.List;

    /**
     * @notice The address of the subgraph data service.
     * @dev Require to handle the special case when the verifier is the subgraph data service.
     */
    address internal immutable SUBGRAPH_DATA_SERVICE_ADDRESS;

    /**
     * @dev The staking contract is upgradeable however we still use the constructor to set
     * a few immutable variables.
     * @param controller The address of the Graph controller contract.
     * @param subgraphDataServiceAddress The address of the subgraph data service.
     */
    constructor(address controller, address subgraphDataServiceAddress) Managed(controller) {
        SUBGRAPH_DATA_SERVICE_ADDRESS = subgraphDataServiceAddress;
    }

    /// @inheritdoc IHorizonStakingBase
    /// @dev Removes deprecated fields from the return value.
    function getServiceProvider(address serviceProvider) external view override returns (ServiceProvider memory) {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = _serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        return sp;
    }

    /// @inheritdoc IHorizonStakingBase
    function getStake(address serviceProvider) external view override returns (uint256) {
        return _serviceProviders[serviceProvider].tokensStaked;
    }

    /// @inheritdoc IHorizonStakingBase
    function getIdleStake(address serviceProvider) external view override returns (uint256) {
        return _getIdleStake(serviceProvider);
    }

    /// @inheritdoc IHorizonStakingBase
    /// @dev Removes deprecated fields from the return value.
    function getDelegationPool(
        address serviceProvider,
        address verifier
    ) external view override returns (DelegationPool memory) {
        DelegationPool memory pool;
        DelegationPoolInternal storage poolInternal = _getDelegationPool(serviceProvider, verifier);
        pool.tokens = poolInternal.tokens;
        pool.shares = poolInternal.shares;
        pool.tokensThawing = poolInternal.tokensThawing;
        pool.sharesThawing = poolInternal.sharesThawing;
        pool.thawingNonce = poolInternal.thawingNonce;
        return pool;
    }

    /// @inheritdoc IHorizonStakingBase
    /// @dev Removes deprecated fields from the return value.
    function getDelegation(
        address serviceProvider,
        address verifier,
        address delegator
    ) external view override returns (Delegation memory) {
        Delegation memory delegation;
        DelegationPoolInternal storage poolInternal = _getDelegationPool(serviceProvider, verifier);
        delegation.shares = poolInternal.delegators[delegator].shares;
        return delegation;
    }

    /// @inheritdoc IHorizonStakingBase
    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType
    ) external view override returns (uint256) {
        return _delegationFeeCut[serviceProvider][verifier][paymentType];
    }

    /// @inheritdoc IHorizonStakingBase
    function getProvision(address serviceProvider, address verifier) external view override returns (Provision memory) {
        return _provisions[serviceProvider][verifier];
    }

    /// @inheritdoc IHorizonStakingBase
    function getTokensAvailable(
        address serviceProvider,
        address verifier,
        uint32 delegationRatio
    ) external view override returns (uint256) {
        uint256 tokensAvailableProvider = _getProviderTokensAvailable(serviceProvider, verifier);
        uint256 tokensAvailableDelegated = _getDelegatedTokensAvailable(serviceProvider, verifier);

        uint256 tokensDelegatedMax = tokensAvailableProvider * (uint256(delegationRatio));
        uint256 tokensDelegatedCapacity = MathUtils.min(tokensAvailableDelegated, tokensDelegatedMax);

        return tokensAvailableProvider + tokensDelegatedCapacity;
    }

    /// @inheritdoc IHorizonStakingBase
    function getProviderTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getProviderTokensAvailable(serviceProvider, verifier);
    }

    /// @inheritdoc IHorizonStakingBase
    function getDelegatedTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getDelegatedTokensAvailable(serviceProvider, verifier);
    }

    /// @inheritdoc IHorizonStakingBase
    function getThawRequest(
        ThawRequestType requestType,
        bytes32 thawRequestId
    ) external view override returns (ThawRequest memory) {
        return _getThawRequest(requestType, thawRequestId);
    }

    /// @inheritdoc IHorizonStakingBase
    function getThawRequestList(
        ThawRequestType requestType,
        address serviceProvider,
        address verifier,
        address owner
    ) external view override returns (LinkedList.List memory) {
        return _getThawRequestList(requestType, serviceProvider, verifier, owner);
    }

    /// @inheritdoc IHorizonStakingBase
    function getThawedTokens(
        ThawRequestType requestType,
        address serviceProvider,
        address verifier,
        address owner
    ) external view override returns (uint256) {
        LinkedList.List storage thawRequestList = _getThawRequestList(requestType, serviceProvider, verifier, owner);
        if (thawRequestList.count == 0) {
            return 0;
        }

        uint256 thawedTokens = 0;
        Provision storage prov = _provisions[serviceProvider][verifier];
        uint256 tokensThawing = prov.tokensThawing;
        uint256 sharesThawing = prov.sharesThawing;

        bytes32 thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0)) {
            ThawRequest storage thawRequest = _getThawRequest(requestType, thawRequestId);
            if (thawRequest.thawingNonce == prov.thawingNonce) {
                if (thawRequest.thawingUntil <= block.timestamp) {
                    // sharesThawing cannot be zero if there is a valid thaw request so the next division is safe
                    uint256 tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
                    tokensThawing = tokensThawing - tokens;
                    sharesThawing = sharesThawing - thawRequest.shares;
                    thawedTokens = thawedTokens + tokens;
                } else {
                    break;
                }
            }

            thawRequestId = thawRequest.nextRequest;
        }
        return thawedTokens;
    }

    /// @inheritdoc IHorizonStakingBase
    function getMaxThawingPeriod() external view override returns (uint64) {
        return _maxThawingPeriod;
    }

    /// @inheritdoc IHorizonStakingBase
    function isAllowedLockedVerifier(address verifier) external view returns (bool) {
        return _allowedLockedVerifiers[verifier];
    }

    /// @inheritdoc IHorizonStakingBase
    function isDelegationSlashingEnabled() external view returns (bool) {
        return _delegationSlashingEnabled;
    }

    /**
     * @notice Deposit tokens into the service provider stake.
     * @dev TRANSITION PERIOD: After transition period move to IHorizonStakingMain. Temporarily it
     * needs to be here since it's used by both {HorizonStaking} and {HorizonStakingExtension}.
     *
     * Emits a {HorizonStakeDeposited} event.
     * @param _serviceProvider The address of the service provider.
     * @param _tokens The amount of tokens to deposit.
     */
    function _stake(address _serviceProvider, uint256 _tokens) internal {
        _serviceProviders[_serviceProvider].tokensStaked = _serviceProviders[_serviceProvider].tokensStaked + _tokens;
        emit HorizonStakeDeposited(_serviceProvider, _tokens);
    }

    /**
     * @notice Gets the service provider's idle stake which is the stake that is not being
     * used for any provision. Note that this only includes service provider's self stake.
     * @dev Note that the calculation considers tokens that were locked in the legacy staking contract.
     * @dev TRANSITION PERIOD: update the calculation after the transition period.
     * @param _serviceProvider The address of the service provider.
     * @return The amount of tokens that are idle.
     */
    function _getIdleStake(address _serviceProvider) internal view returns (uint256) {
        uint256 tokensUsed = _serviceProviders[_serviceProvider].tokensProvisioned +
            _serviceProviders[_serviceProvider].__DEPRECATED_tokensAllocated +
            _serviceProviders[_serviceProvider].__DEPRECATED_tokensLocked;
        uint256 tokensStaked = _serviceProviders[_serviceProvider].tokensStaked;
        return tokensStaked > tokensUsed ? tokensStaked - tokensUsed : 0;
    }

    /**
     * @notice Gets the details of delegation pool.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the pools are stored in the legacy mapping.
     * @param _serviceProvider The address of the service provider.
     * @param _verifier The address of the verifier.
     * @return The delegation pool details.
     */
    function _getDelegationPool(
        address _serviceProvider,
        address _verifier
    ) internal view returns (DelegationPoolInternal storage) {
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return _legacyDelegationPools[_serviceProvider];
        } else {
            return _delegationPools[_serviceProvider][_verifier];
        }
    }

    /**
     * @notice Gets the service provider's tokens available in a provision.
     * @dev Calculated as the tokens available minus the tokens thawing.
     * @param _serviceProvider The address of the service provider.
     * @param _verifier The address of the verifier.
     * @return The amount of tokens available.
     */
    function _getProviderTokensAvailable(address _serviceProvider, address _verifier) internal view returns (uint256) {
        return _provisions[_serviceProvider][_verifier].tokens - _provisions[_serviceProvider][_verifier].tokensThawing;
    }

    /**
     * @notice Retrieves the next thaw request for a provision.
     * @param _thawRequestId The ID of the current thaw request.
     * @return The ID of the next thaw request in the list.
     */
    function _getNextProvisionThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _thawRequests[ThawRequestType.Provision][_thawRequestId].nextRequest;
    }

    /**
     * @notice Retrieves the next thaw request for a delegation.
     * @param _thawRequestId The ID of the current thaw request.
     * @return The ID of the next thaw request in the list.
     */
    function _getNextDelegationThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _thawRequests[ThawRequestType.Delegation][_thawRequestId].nextRequest;
    }

    /**
     * @notice Retrieves the thaw request list for the given request type.
     * @dev Uses the `ThawRequestType` to determine which mapping to access.
     * Reverts if the request type is unknown.
     * @param _requestType The type of thaw request (Provision or Delegation).
     * @param _serviceProvider The address of the service provider.
     * @param _verifier The address of the verifier.
     * @param _owner The address of the owner of the thaw request.
     * @return The linked list of thaw requests for the specified request type.
     */
    function _getThawRequestList(
        ThawRequestType _requestType,
        address _serviceProvider,
        address _verifier,
        address _owner
    ) internal view returns (LinkedList.List storage) {
        return _thawRequestLists[_requestType][_serviceProvider][_verifier][_owner];
    }

    /**
     * @notice Retrieves a specific thaw request for the given request type.
     * @dev Uses the `ThawRequestType` to determine which mapping to access.
     * @param _requestType The type of thaw request (Provision or Delegation).
     * @param _thawRequestId The unique ID of the thaw request.
     * @return The thaw request data for the specified request type and ID.
     */
    function _getThawRequest(
        ThawRequestType _requestType,
        bytes32 _thawRequestId
    ) internal view returns (IHorizonStakingTypes.ThawRequest storage) {
        return _thawRequests[_requestType][_thawRequestId];
    }

    /**
     * @notice Determines the correct callback function for `getNextItem` based on the request type.
     * @param _requestType The type of thaw request (Provision or Delegation).
     * @return A function pointer to the appropriate `getNextItem` callback.
     */
    function _getNextThawRequest(
        ThawRequestType _requestType
    ) internal pure returns (function(bytes32) view returns (bytes32)) {
        if (_requestType == ThawRequestType.Provision) {
            return _getNextProvisionThawRequest;
        } else if (_requestType == ThawRequestType.Delegation) {
            return _getNextDelegationThawRequest;
        } else {
            revert HorizonStakingInvalidThawRequestType();
        }
    }

    /**
     * @notice Gets the delegator's tokens available in a provision.
     * @dev Calculated as the tokens available minus the tokens thawing.
     * @param _serviceProvider The address of the service provider.
     * @param _verifier The address of the verifier.
     * @return The amount of tokens available.
     */
    function _getDelegatedTokensAvailable(address _serviceProvider, address _verifier) private view returns (uint256) {
        DelegationPoolInternal storage poolInternal = _getDelegationPool(_serviceProvider, _verifier);
        return poolInternal.tokens - poolInternal.tokensThawing;
    }
}
