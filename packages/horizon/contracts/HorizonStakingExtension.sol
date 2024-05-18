// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { StakingBackwardsCompatibility } from "./StakingBackwardsCompatibility.sol";
import { IL2StakingBase } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingBase.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";
import { IHorizonStakingExtension } from "./IHorizonStakingExtension.sol";
import { MathUtils } from "./utils/MathUtils.sol";

act
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
        address _controller,
        address _subgraphDataServiceAddress,
        address _exponentialRebates
    ) StakingBackwardsCompatibility(_controller, _subgraphDataServiceAddress, _exponentialRebates) {}

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
        return serviceProviders[serviceProvider].tokensStaked;
    }

    // provisioned tokens from delegators that are not being thawed
    // `Provision.delegatedTokens - Provision.delegatedTokensThawing`
    function getDelegatedTokensAvailable(
        address _serviceProvider,
        address _verifier
    ) public view override returns (uint256) {
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return
                legacyDelegationPools[_serviceProvider].tokens -
                (legacyDelegationPools[_serviceProvider].tokensThawing);
        }
        return
            delegationPools[_serviceProvider][_verifier].tokens -
            (delegationPools[_serviceProvider][_verifier].tokensThawing);
    }

    // provisioned tokens that are not being thawed (including provider tokens and delegation)
    function getTokensAvailable(
        address _serviceProvider,
        address _verifier,
        uint32 _delegationRatio
    ) external view override returns (uint256) {
        uint256 providerTokens = provisions[_serviceProvider][_verifier].tokens;
        uint256 tokensDelegatedMax = providerTokens * (uint256(_delegationRatio));
        uint256 tokensDelegatedCapacity = MathUtils.min(
            getDelegatedTokensAvailable(_serviceProvider, _verifier),
            tokensDelegatedMax
        );
        return providerTokens - provisions[_serviceProvider][_verifier].tokensThawing + tokensDelegatedCapacity;
    }

    function getServiceProvider(address serviceProvider) external view override returns (ServiceProvider memory) {
        ServiceProvider memory sp;
        ServiceProviderInternal storage spInternal = serviceProviders[serviceProvider];
        sp.tokensStaked = spInternal.tokensStaked;
        sp.tokensProvisioned = spInternal.tokensProvisioned;
        sp.nextThawRequestNonce = spInternal.nextThawRequestNonce;
        return sp;
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller on a data service.
     * @param _operator Address to authorize or unauthorize
     * @param _verifier The verifier / data service on which they'll be allowed to operate
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, address _verifier, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            legacyOperatorAuth[msg.sender][_operator] = _allowed;
        } else {
            operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        }
        emit OperatorSet(msg.sender, _operator, _verifier, _allowed);
    }

    // for vesting contracts
    function setOperatorLocked(address _operator, address _verifier, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        require(allowedLockedVerifiers[_verifier], "VERIFIER_NOT_ALLOWED");
        operatorAuth[msg.sender][_verifier][_operator] = _allowed;
        emit OperatorSet(msg.sender, _operator, _verifier, _allowed);
    }

    function getMaxThawingPeriod() external view override returns (uint64) {
        return maxThawingPeriod;
    }

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * @dev The encoded _data can contain information about an indexer's stake
     * or a delegator's delegation.
     * See L1MessageCodes in IL2Staking for the supported messages.
     * @param _from Token sender in L1
     * @param _amount Amount of tokens that were transferred
     * @param _data ABI-encoded callhook data which must include a uint8 code and either a ReceiveIndexerStakeData or ReceiveDelegationData struct.
     */
    function onTokenTransfer(
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external override notPartialPaused onlyL2Gateway {
        require(_from == counterpartStakingAddress, "ONLY_L1_STAKING_THROUGH_BRIDGE");
        (uint8 code, bytes memory functionData) = abi.decode(_data, (uint8, bytes));

        if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_INDEXER_STAKE_CODE)) {
            IL2StakingTypes.ReceiveIndexerStakeData memory indexerData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveIndexerStakeData)
            );
            _receiveIndexerStake(_amount, indexerData);
        } else if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE)) {
            IL2StakingTypes.ReceiveDelegationData memory delegationData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveDelegationData)
            );
            _receiveDelegation(_amount, delegationData);
        } else {
            revert("INVALID_CODE");
        }
    }

    function getDelegationPool(
        address _serviceProvider,
        address _verifier
    ) external view override returns (DelegationPool memory) {
        DelegationPool memory pool;
        DelegationPoolInternal storage poolInternal;
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            poolInternal = legacyDelegationPools[_serviceProvider];
        } else {
            poolInternal = delegationPools[_serviceProvider][_verifier];
        }
        pool.tokens = poolInternal.tokens;
        pool.shares = poolInternal.shares;
        pool.tokensThawing = poolInternal.tokensThawing;
        pool.sharesThawing = poolInternal.sharesThawing;
        return pool;
    }

    function getDelegation(
        address _delegator,
        address _serviceProvider,
        address _verifier
    ) external view override returns (Delegation memory) {
        if (_verifier == SUBGRAPH_DATA_SERVICE_ADDRESS) {
            return legacyDelegationPools[_serviceProvider].delegators[_delegator];
        } else {
            return delegationPools[_serviceProvider][_verifier].delegators[_delegator];
        }
    }

    function getThawRequest(bytes32 _thawRequestId) external view returns (ThawRequest memory) {
        return thawRequests[_thawRequestId];
    }

    function getProvision(
        address _serviceProvider,
        address _verifier
    ) external view override returns (Provision memory) {
        return provisions[_serviceProvider][_verifier];
    }

    function setDelegationFeeCut(
        address _serviceProvider,
        address _verifier,
        uint256 _feeType,
        uint256 _feeCut
    ) external override {
        delegationFeeCut[_serviceProvider][_verifier][_feeType] = _feeCut;
        emit DelegationFeeCutSet(_serviceProvider, _verifier, _feeType, _feeCut);
    }

    function getDelegationFeeCut(
        address _serviceProvider,
        address _verifier,
        uint256 _feeType
    ) external view override returns (uint256) {
        return delegationFeeCut[_serviceProvider][_verifier][_feeType];
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
        address _indexer = _indexerData.indexer;
        // Deposit tokens into the indexer stake
        _stake(_indexer, _amount);
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
        DelegationPoolInternal storage pool = legacyDelegationPools[_delegationData.indexer];
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
