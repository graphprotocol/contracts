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

    /**
     * @notice Receive ETH into the Staking contract: this will always revert
     * @dev This function is only here to prevent ETH from being sent to the contract
     */
    receive() external payable {
        revert("RECEIVE_ETH_NOT_ALLOWED");
    }

    /**
     * @notice See {IHorizonStakingBase-getServiceProvider}.
     * @dev Removes deprecated fields from the return value.
     */
    function getServiceProvider(address serviceProvider) external view override returns (ServiceProvider memory) {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = _serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        return sp;
    }

    /**
     * @notice See {IHorizonStakingBase-getStake}.
     */
    function getStake(address serviceProvider) external view override returns (uint256) {
        return _serviceProviders[serviceProvider].tokensStaked;
    }

    /**
     * @notice See {IHorizonStakingBase-getIdleStake}.
     */
    function getIdleStake(address serviceProvider) external view override returns (uint256 tokens) {
        return _getIdleStake(serviceProvider);
    }

    /**
     * @notice See {IHorizonStakingBase-getDelegationPool}.
     * @dev Removes deprecated fields from the return value.
     */
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

    /**
     * @notice See {IHorizonStakingBase-getDelegation}.
     * @dev Removes deprecated fields from the return value.
     */
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

    /**
     * @notice See {IHorizonStakingBase-getDelegationFeeCut}.
     */
    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType
    ) external view override returns (uint256) {
        return _delegationFeeCut[serviceProvider][verifier][paymentType];
    }

    /**
     * @notice See {IHorizonStakingBase-getProvision}.
     */
    function getProvision(address serviceProvider, address verifier) external view override returns (Provision memory) {
        return _provisions[serviceProvider][verifier];
    }

    /**
     * @notice See {IHorizonStakingBase-getTokensAvailable}.
     */
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

    /**
     * @notice See {IHorizonStakingBase-getProviderTokensAvailable}.
     */
    function getProviderTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getProviderTokensAvailable(serviceProvider, verifier);
    }

    /**
     * @notice See {IHorizonStakingBase-getDelegatedTokensAvailable}.
     */
    function getDelegatedTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getDelegatedTokensAvailable(serviceProvider, verifier);
    }

    /**
     * @notice See {IHorizonStakingBase-getThawRequest}.
     */
    function getThawRequest(
        ThawRequestType requestType,
        bytes32 thawRequestId
    ) external view override returns (ThawRequest memory) {
        return _getThawRequest(requestType, thawRequestId);
    }

    /**
     * @notice See {IHorizonStakingBase-getThawRequestList}.
     */
    function getThawRequestList(
        ThawRequestType requestType,
        address serviceProvider,
        address verifier,
        address owner
    ) external view override returns (LinkedList.List memory) {
        return _getThawRequestList(requestType, serviceProvider, verifier, owner);
    }

    /**
     * @notice See {IHorizonStakingBase-getThawedTokens}.
     */
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
            if (thawRequest.thawingUntil <= block.timestamp) {
                uint256 tokens = (thawRequest.shares * tokensThawing) / sharesThawing;
                tokensThawing = tokensThawing - tokens;
                sharesThawing = sharesThawing - thawRequest.shares;
                thawedTokens = thawedTokens + tokens;
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }
        return thawedTokens;
    }

    /**
     * @notice See {IHorizonStakingBase-getMaxThawingPeriod}.
     */
    function getMaxThawingPeriod() external view override returns (uint64) {
        return _maxThawingPeriod;
    }

    /**
     * @notice see {IHorizonStakingBase-isAllowedLockedVerifier}.
     */
    function isAllowedLockedVerifier(address verifier) external view returns (bool) {
        return _allowedLockedVerifiers[verifier];
    }

    /**
     * @notice See {IHorizonStakingBase-isDelegationSlashingEnabled}.
     */
    function isDelegationSlashingEnabled() external view returns (bool) {
        return _delegationSlashingEnabled;
    }

    /**
     * @notice Deposit tokens into the service provider stake.
     * @dev TODO: After transition period move to IHorizonStakingMain. Temporarily it
     * needs to be here since it's used by both {HorizonStaking} and {HorizonStakingExtension}.
     *
     * Emits a {StakeDeposited} event.
     * @param _serviceProvider The address of the service provider.
     * @param _tokens The amount of tokens to deposit.
     */
    function _stake(address _serviceProvider, uint256 _tokens) internal {
        _serviceProviders[_serviceProvider].tokensStaked = _serviceProviders[_serviceProvider].tokensStaked + _tokens;
        emit StakeDeposited(_serviceProvider, _tokens);
    }

    /**
     * @notice See {IHorizonStakingBase-getIdleStake}.
     * @dev Note that the calculation considers tokens that were locked in the legacy staking contract.
     * TODO: update the calculation after the transition period.
     */
    function _getIdleStake(address _serviceProvider) internal view returns (uint256) {
        return
            _serviceProviders[_serviceProvider].tokensStaked -
            _serviceProviders[_serviceProvider].tokensProvisioned -
            _serviceProviders[_serviceProvider].__DEPRECATED_tokensAllocated -
            _serviceProviders[_serviceProvider].__DEPRECATED_tokensLocked;
    }

    /**
     * @notice See {IHorizonStakingBase-getDelegationPool}.
     * @dev Note that this function handles the special case where the verifier is the subgraph data service,
     * where the pools are stored in the legacy mapping.
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
     * @notice See {IHorizonStakingBase-getProviderTokensAvailable}.
     */
    function _getProviderTokensAvailable(address _serviceProvider, address _verifier) internal view returns (uint256) {
        return _provisions[_serviceProvider][_verifier].tokens - _provisions[_serviceProvider][_verifier].tokensThawing;
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
        } else if (_requestType == ThawRequestType.DelegationWithBeneficiary) {
            return _getNextDelegationWithBeneficiaryThawRequest;
        } else {
            revert HorizonStakingInvalidThawRequestType();
        }
    }

    /**
     * @notice Retrieves the next thaw request for a provision.
     * @param _thawRequestId The ID of the current thaw request.
     * @return The ID of the next thaw request in the list.
     */
    function _getNextProvisionThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _provisionThawRequests[_thawRequestId].next;
    }

    /**
     * @notice Retrieves the next thaw request for a delegation.
     * @param _thawRequestId The ID of the current thaw request.
     * @return The ID of the next thaw request in the list.
     */
    function _getNextDelegationThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _delegationThawRequests[_thawRequestId].next;
    }

    /**
     * @notice Retrieves the next thaw request for a delegation with a beneficiary.
     * @param _thawRequestId The ID of the current thaw request.
     * @return The ID of the next thaw request in the list.
     */
    function _getNextDelegationWithBeneficiaryThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _delegationWithBeneficiaryThawRequests[_thawRequestId].next;
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
        if (_requestType == ThawRequestType.Provision) {
            return _provisionThawRequestLists[_serviceProvider][_verifier][_owner];
        } else if (_requestType == ThawRequestType.Delegation) {
            return _delegationThawRequestLists[_serviceProvider][_verifier][_owner];
        } else if (_requestType == ThawRequestType.DelegationWithBeneficiary) {
            return _delegationWithBeneficiaryThawRequestLists[_serviceProvider][_verifier][_owner];
        } else {
            revert HorizonStakingInvalidThawRequestType();
        }
    }

    /**
     * @notice Retrieves a specific thaw request for the given request type.
     * @dev Uses the `ThawRequestType` to determine which mapping to access.
     * Reverts if the request type is unknown.
     * @param _requestType The type of thaw request (Provision or Delegation).
     * @param _thawRequestId The unique ID of the thaw request.
     * @return The thaw request data for the specified request type and ID.
     */
    function _getThawRequest(
        ThawRequestType _requestType,
        bytes32 _thawRequestId
    ) internal view returns (IHorizonStakingTypes.ThawRequest storage) {
        if (_requestType == ThawRequestType.Provision) {
            return _provisionThawRequests[_thawRequestId];
        } else if (_requestType == ThawRequestType.Delegation) {
            return _delegationThawRequests[_thawRequestId];
        } else if (_requestType == ThawRequestType.DelegationWithBeneficiary) {
            return _delegationWithBeneficiaryThawRequests[_thawRequestId];
        } else {
            revert("Unknown ThawRequestType");
        }
    }

    /**
     * @notice See {IHorizonStakingBase-getDelegatedTokensAvailable}.
     */
    function _getDelegatedTokensAvailable(address _serviceProvider, address _verifier) private view returns (uint256) {
        DelegationPoolInternal storage poolInternal = _getDelegationPool(_serviceProvider, _verifier);
        return poolInternal.tokens - poolInternal.tokensThawing;
    }
}
