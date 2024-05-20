// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IL2StakingBase } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingBase.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";
import { IHorizonStakingExtension } from "../interfaces/IHorizonStakingExtension.sol";

import { MathUtils } from "../libraries/MathUtils.sol";

import { StakingBackwardsCompatibility } from "./StakingBackwardsCompatibility.sol";

/**
 * @title L2Staking contract
 * @dev This contract is the L2 variant of the Staking contract. It adds a function
 * to receive an indexer's stake or delegation from L1. Note that this contract inherits Staking,
 * which uses a StakingExtension contract to implement the full IStaking interface through delegatecalls.
 */
contract HorizonStakingExtension is StakingBackwardsCompatibility, IHorizonStakingExtension, IL2StakingBase {
    /// @dev Minimum amount of tokens that can be delegated
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == GRAPH_TOKEN_GATEWAY, "ONLY_GATEWAY");
        _;
    }

    constructor(
        address controller,
        address subgraphDataServiceAddress
    ) StakingBackwardsCompatibility(controller, subgraphDataServiceAddress) {}

    /**
     * @notice Receive ETH into the Staking contract: this will always revert
     * @dev This function is only here to prevent ETH from being sent to the contract
     */
    receive() external payable {
        revert("RECEIVE_ETH_NOT_ALLOWED");
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param operator Address to authorize or unauthorize
     * @param verifier The verifier / data service on which they'll be allowed to operate
     * @param allowed Whether the operator is authorized or not
     */
    function setOperator(address operator, address verifier, bool allowed) external override {
        require(operator != msg.sender, "operator == sender");
        if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            _legacyOperatorAuth[msg.sender][operator] = allowed;
        } else {
            _operatorAuth[msg.sender][verifier][operator] = allowed;
        }
        emit OperatorSet(msg.sender, operator, verifier, allowed);
    }

    // for vesting contracts
    function setOperatorLocked(address operator, address verifier, bool allowed) external override {
        require(operator != msg.sender, "operator == sender");
        require(_allowedLockedVerifiers[verifier], "VERIFIER_NOT_ALLOWED");
        _operatorAuth[msg.sender][verifier][operator] = allowed;
        emit OperatorSet(msg.sender, operator, verifier, allowed);
    }

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * @dev The encoded _data can contain information about an indexer's stake
     * or a delegator's delegation.
     * See L1MessageCodes in IL2Staking for the supported messages.
     * @param from Token sender in L1
     * @param amount Amount of tokens that were transferred
     * @param data ABI-encoded callhook data which must include a uint8 code and either a ReceiveIndexerStakeData or ReceiveDelegationData struct.
     */
    function onTokenTransfer(
        address from,
        uint256 amount,
        bytes calldata data
    ) external override notPartialPaused onlyL2Gateway {
        require(from == _counterpartStakingAddress, "ONLY_L1_STAKING_THROUGH_BRIDGE");
        (uint8 code, bytes memory functionData) = abi.decode(data, (uint8, bytes));

        if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_INDEXER_STAKE_CODE)) {
            IL2StakingTypes.ReceiveIndexerStakeData memory indexerData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveIndexerStakeData)
            );
            _receiveIndexerStake(amount, indexerData);
        } else if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE)) {
            IL2StakingTypes.ReceiveDelegationData memory delegationData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveDelegationData)
            );
            _receiveDelegation(amount, delegationData);
        } else {
            revert("INVALID_CODE");
        }
    }

    function setDelegationFeeCut(
        address serviceProvider,
        address verifier,
        uint256 feeType,
        uint256 feeCut
    ) external override {
        delegationFeeCut[serviceProvider][verifier][feeType] = feeCut;
        emit DelegationFeeCutSet(serviceProvider, verifier, feeType, feeCut);
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
        uint256 tokensDelegatedMax = providerTokens * (uint256(delegationRatio));
        uint256 tokensDelegatedCapacity = MathUtils.min(
            getDelegatedTokensAvailable(serviceProvider, verifier),
            tokensDelegatedMax
        );
        return providerTokens - _provisions[serviceProvider][verifier].tokensThawing + tokensDelegatedCapacity;
    }

    function getServiceProvider(address serviceProvider) external view override returns (ServiceProvider memory) {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = _serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        sp.nextThawRequestNonce = spInternal.nextThawRequestNonce;
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
        DelegationPoolInternal storage poolInternal;
        if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            poolInternal = _legacyDelegationPools[serviceProvider];
        } else {
            poolInternal = _delegationPools[serviceProvider][verifier];
        }
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
        if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return _legacyDelegationPools[serviceProvider].delegators[delegator];
        } else {
            return _delegationPools[serviceProvider][verifier].delegators[delegator];
        }
    }

    function getThawRequest(bytes32 thawRequestId) external view returns (ThawRequest memory) {
        return _thawRequests[thawRequestId];
    }

    function getProvision(address serviceProvider, address verifier) external view override returns (Provision memory) {
        return _provisions[serviceProvider][verifier];
    }

    function getDelegationFeeCut(
        address serviceProvider,
        address verifier,
        uint256 feeType
    ) external view override returns (uint256) {
        return delegationFeeCut[serviceProvider][verifier][feeType];
    }

    // provisioned tokens from delegators that are not being thawed
    // `Provision.delegatedTokens - Provision.delegatedTokensThawing`
    function getDelegatedTokensAvailable(
        address serviceProvider,
        address verifier
    ) public view override returns (uint256) {
        if (verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return
                _legacyDelegationPools[serviceProvider].tokens -
                (_legacyDelegationPools[serviceProvider].tokensThawing);
        }
        return
            _delegationPools[serviceProvider][verifier].tokens -
            (_delegationPools[serviceProvider][verifier].tokensThawing);
    }

    /**
     * @dev Receive an Indexer's stake from L1.
     * The specified amount is added to the indexer's stake; the indexer's
     * address is specified in the _indexerData struct.
     * @param _amount Amount of tokens that were transferred
     * @param _indexerData struct containing the indexer's address
     */
    function _receiveIndexerStake(
        uint256 _amount,
        IL2StakingTypes.ReceiveIndexerStakeData memory _indexerData
    ) internal {
        address indexer = _indexerData.indexer;
        // Deposit tokens into the indexer stake
        _stake(indexer, _amount);
    }

    /**
     * @dev Receive a Delegator's delegation from L1.
     * The specified amount is added to the delegator's delegation; the delegator's
     * address and the indexer's address are specified in the _delegationData struct.
     * Note that no delegation tax is applied here.
     * @param _amount Amount of tokens that were transferred
     * @param _delegationData struct containing the delegator's address and the indexer's address
     */
    function _receiveDelegation(
        uint256 _amount,
        IL2StakingTypes.ReceiveDelegationData memory _delegationData
    ) internal {
        // Get the delegation pool of the indexer
        DelegationPoolInternal storage pool = _legacyDelegationPools[_delegationData.indexer];
        Delegation storage delegation = pool.delegators[_delegationData.delegator];

        // Calculate shares to issue (without applying any delegation tax)
        uint256 shares = (pool.tokens == 0) ? _amount : ((_amount * pool.shares) / pool.tokens);

        if (shares == 0 || _amount < MINIMUM_DELEGATION) {
            // If no shares would be issued (probably a rounding issue or attack),
            // or if the amount is under the minimum delegation (which could be part of a rounding attack),
            // return the tokens to the delegator
            _graphToken().transfer(_delegationData.delegator, _amount);
            emit TransferredDelegationReturnedToDelegator(_delegationData.indexer, _delegationData.delegator, _amount);
        } else {
            // Update the delegation pool
            pool.tokens = pool.tokens + _amount;
            pool.shares = pool.shares + shares;

            // Update the individual delegation
            delegation.shares = delegation.shares + shares;

            emit StakeDelegated(_delegationData.indexer, _delegationData.delegator, _amount, shares);
        }
    }
}
