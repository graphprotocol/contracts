// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

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
 * @title L2Staking contract
 * @dev This contract is the L2 variant of the Staking contract. It adds a function
 * to receive an service provider's stake or delegation from L1. Note that this contract inherits Staking,
 * which uses a StakingExtension contract to implement the full IStaking interface through delegatecalls.
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

    address internal immutable SUBGRAPH_DATA_SERVICE_ADDRESS;

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

    // total staked tokens to the provider
    // `ServiceProvider.tokensStaked
    function getStake(address serviceProvider) external view override returns (uint256) {
        return _serviceProviders[serviceProvider].tokensStaked;
    }

    // provisioned tokens that are not being thawed (including provider tokens and delegation)
    function getTokensAvailable(
        address serviceProvider,
        address verifier,
        uint32 delegationRatio
    ) external view override returns (uint256) {
        uint256 providerTokens = _provisions[serviceProvider][verifier].tokens;
        uint256 providerThawingTokens = _provisions[serviceProvider][verifier].tokensThawing;
        uint256 tokensDelegatedMax = (providerTokens - providerThawingTokens) * (uint256(delegationRatio));
        uint256 tokensDelegatedCapacity = MathUtils.min(
            _getDelegatedTokensAvailable(serviceProvider, verifier),
            tokensDelegatedMax
        );
        return providerTokens - providerThawingTokens + tokensDelegatedCapacity;
    }

    function getServiceProvider(address serviceProvider) external view override returns (ServiceProvider memory) {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = _serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        return sp;
    }

    function getMaxThawingPeriod() external view override returns (uint64) {
        return _maxThawingPeriod;
    }

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
        return pool;
    }

    function getDelegation(
        address delegator,
        address serviceProvider,
        address verifier
    ) external view override returns (Delegation memory) {
        DelegationPoolInternal storage poolInternal = _getDelegationPool(serviceProvider, verifier);
        return poolInternal.delegators[delegator];
    }

    function getThawRequest(bytes32 thawRequestId) external view returns (ThawRequest memory) {
        return _thawRequests[thawRequestId];
    }

    function getThawRequestList(
        address serviceProvider,
        address verifier,
        address owner
    ) external view returns (LinkedList.List memory) {
        return _thawRequestLists[serviceProvider][verifier][owner];
    }

    function getProvision(address serviceProvider, address verifier) external view override returns (Provision memory) {
        return _provisions[serviceProvider][verifier];
    }

    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        IGraphPayments.PaymentTypes paymentType
    ) external view override returns (uint256) {
        return delegationFeeCut[serviceProvider][verifier][paymentType];
    }

    // provisioned tokens from delegators that are not being thawed
    // `Provision.delegatedTokens - Provision.delegatedTokensThawing`
    function getDelegatedTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getDelegatedTokensAvailable(serviceProvider, verifier);
    }

    // staked tokens that are currently not provisioned, aka idle stake
    // `getStake(serviceProvider) - ServiceProvider.tokensProvisioned`
    function getIdleStake(address serviceProvider) external view override returns (uint256 tokens) {
        return _getIdleStake(serviceProvider);
    }

    // provisioned tokens from the service provider that are not being thawed
    // `Provision.tokens - Provision.tokensThawing`
    function getProviderTokensAvailable(
        address serviceProvider,
        address verifier
    ) external view override returns (uint256) {
        return _getProviderTokensAvailable(serviceProvider, verifier);
    }

    /**
     * @notice Get the amount of service provider's tokens in a provision that have finished thawing
     * @param serviceProvider The service provider address
     * @param verifier The verifier address for which the tokens are provisioned
     */
    function getThawedTokens(address serviceProvider, address verifier) external view returns (uint256) {
        LinkedList.List storage thawRequestList = _thawRequestLists[serviceProvider][verifier][serviceProvider];
        if (thawRequestList.count == 0) {
            return 0;
        }

        uint256 tokens = 0;
        Provision storage prov = _provisions[serviceProvider][verifier];

        bytes32 thawRequestId = thawRequestList.head;
        while (thawRequestId != bytes32(0)) {
            ThawRequest storage thawRequest = _thawRequests[thawRequestId];
            if (thawRequest.thawingUntil <= block.timestamp) {
                tokens += (thawRequest.shares * prov.tokensThawing) / prov.sharesThawing;
            } else {
                break;
            }
            thawRequestId = thawRequest.next;
        }
        return tokens;
    }

    /**
     * @notice Deposit tokens into the service provider stake.
     * @dev TODO(after transition period): move to HorizonStaking
     * @param _serviceProvider Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _serviceProvider, uint256 _tokens) internal {
        _serviceProviders[_serviceProvider].tokensStaked = _serviceProviders[_serviceProvider].tokensStaked + _tokens;
        emit StakeDeposited(_serviceProvider, _tokens);
    }

    function _getNextThawRequest(bytes32 _thawRequestId) internal view returns (bytes32) {
        return _thawRequests[_thawRequestId].next;
    }

    function _getDelegationPool(
        address _serviceProvider,
        address _verifier
    ) internal view returns (DelegationPoolInternal storage) {
        IHorizonStakingTypes.DelegationPoolInternal storage pool;
        if (_verifier == _serviceProvider) {
            pool = _legacyDelegationPools[_serviceProvider];
        } else {
            pool = _delegationPools[_serviceProvider][_verifier];
        }
        return pool;
    }

    function _getIdleStake(address _serviceProvider) internal view returns (uint256 tokens) {
        return
            _serviceProviders[_serviceProvider].tokensStaked -
            _serviceProviders[_serviceProvider].tokensProvisioned -
            _serviceProviders[_serviceProvider].__DEPRECATED_tokensLocked;
    }

    function _getProviderTokensAvailable(address _serviceProvider, address _verifier) internal view returns (uint256) {
        return _provisions[_serviceProvider][_verifier].tokens - _provisions[_serviceProvider][_verifier].tokensThawing;
    }

    function _getDelegatedTokensAvailable(address _serviceProvider, address _verifier) internal view returns (uint256) {
        DelegationPoolInternal storage poolInternal = _getDelegationPool(_serviceProvider, _verifier);
        return poolInternal.tokens - poolInternal.tokensThawing;
    }
}
