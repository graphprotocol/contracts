// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";
import { IRewardsIssuer } from "@graphprotocol/contracts/contracts/rewards/IRewardsIssuer.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStakingExtension } from "../interfaces/internal/IHorizonStakingExtension.sol";
import { IHorizonStakingTypes } from "../interfaces/internal/IHorizonStakingTypes.sol";
import { IL2StakingTypes } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingTypes.sol";
import { IL2StakingBase } from "@graphprotocol/contracts/contracts/l2/staking/IL2StakingBase.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { MathUtils } from "../libraries/MathUtils.sol";
import { ExponentialRebates } from "./libraries/ExponentialRebates.sol";
import { PPMMath } from "../libraries/PPMMath.sol";

import { HorizonStakingBase } from "./HorizonStakingBase.sol";

/**
 * @title Base Staking contract
 * @dev The Staking contract allows Indexers to Stake on Subgraphs. Indexers Stake by creating
 * Allocations on a Subgraph. It also allows Delegators to Delegate towards an Indexer. The
 * contract also has the slashing functionality.
 * The contract is abstract as the implementation that is deployed depends on each layer: L1Staking on mainnet
 * and L2Staking on Arbitrum.
 * Note that this contract delegates part of its functionality to a StakingExtension contract.
 * This is due to the 24kB contract size limit on Ethereum.
 */
contract HorizonStakingExtension is HorizonStakingBase, IRewardsIssuer, IL2StakingBase, IHorizonStakingExtension {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;

    /// @dev Minimum amount of tokens that can be delegated
    uint256 private constant MINIMUM_DELEGATION = 1e18;

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == address(_graphTokenGateway()), "ONLY_GATEWAY");
        _;
    }

    constructor(
        address controller,
        address subgraphDataServiceAddress
    ) HorizonStakingBase(controller, subgraphDataServiceAddress) {}

    /**
     * @notice Receive tokens with a callhook from the bridge.
     * @dev The encoded _data can contain information about an service provider's stake
     * or a delegator's delegation.
     * See L1MessageCodes in IL2Staking for the supported messages.
     * @dev "indexer" in this context refers to a service provider (legacy terminology for the bridge)
     * @param from Token sender in L1
     * @param tokens Amount of tokens that were transferred
     * @param data ABI-encoded callhook data which must include a uint8 code and either a ReceiveIndexerStakeData or ReceiveDelegationData struct.
     */
    function onTokenTransfer(
        address from,
        uint256 tokens,
        bytes calldata data
    ) external override notPartialPaused onlyL2Gateway {
        require(from == _counterpartStakingAddress, "ONLY_L1_STAKING_THROUGH_BRIDGE");
        (uint8 code, bytes memory functionData) = abi.decode(data, (uint8, bytes));

        if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_INDEXER_STAKE_CODE)) {
            IL2StakingTypes.ReceiveIndexerStakeData memory indexerData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveIndexerStakeData)
            );
            _receiveIndexerStake(tokens, indexerData);
        } else if (code == uint8(IL2StakingTypes.L1MessageCodes.RECEIVE_DELEGATION_CODE)) {
            IL2StakingTypes.ReceiveDelegationData memory delegationData = abi.decode(
                functionData,
                (IL2StakingTypes.ReceiveDelegationData)
            );
            _receiveDelegation(tokens, delegationData);
        } else {
            revert("INVALID_CODE");
        }
    }

    /**
     * @notice Set the address of the counterpart (L1 or L2) staking contract.
     * @dev This function can only be called by the governor.
     * TODO: Remove after L2 transition period
     * @param counterpart Address of the counterpart staking contract in the other chain, without any aliasing.
     */
    function setCounterpartStakingAddress(address counterpart) external override onlyGovernor {
        _counterpartStakingAddress = counterpart;
        emit CounterpartStakingAddressSet(counterpart);
    }

    /**
     * @notice Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out of rewards set _poi to 0x0
     * @dev TODO: Remove after Horizon transition period
     * @param allocationID The allocation identifier
     * @param poi Proof of indexing submitted for the allocated period
     */
    function closeAllocation(address allocationID, bytes32 poi) external override notPaused {
        _closeAllocation(allocationID, poi);
    }

    /**
     * @dev Collect and rebate query fees from state channels to the indexer
     * To avoid reverting on the withdrawal from channel flow this function will accept calls with zero tokens.
     * We use an exponential rebate formula to calculate the amount of tokens to rebate to the indexer.
     * This implementation allows collecting multiple times on the same allocation, keeping track of the
     * total amount rebated, the total amount collected and compensating the indexer for the difference.
     * TODO: Remove after Horizon transition period
     * @param tokens Amount of tokens to collect
     * @param allocationID Allocation where the tokens will be assigned
     */
    function collect(uint256 tokens, address allocationID) external override {
        // Allocation identifier validation
        require(allocationID != address(0), "!alloc");

        // Allocation must exist
        AllocationState allocState = _getAllocationState(allocationID);
        require(allocState != AllocationState.Null, "!collect");

        // If the query fees are zero, we don't want to revert
        // but we also don't need to do anything, so just return
        if (tokens == 0) {
            return;
        }

        Allocation storage alloc = __DEPRECATED_allocations[allocationID];
        bytes32 subgraphDeploymentID = alloc.subgraphDeploymentID;

        uint256 queryFees = tokens; // Tokens collected from the channel
        uint256 protocolTax = 0; // Tokens burnt as protocol tax
        uint256 curationFees = 0; // Tokens distributed to curators as curation fees
        uint256 queryRebates = 0; // Tokens to distribute to indexer
        uint256 delegationRewards = 0; // Tokens to distribute to delegators

        {
            // -- Pull tokens from the sender --
            _graphToken().pullTokens(msg.sender, queryFees);

            // -- Collect protocol tax --
            protocolTax = _collectTax(queryFees, __DEPRECATED_protocolPercentage);
            queryFees = queryFees - protocolTax;

            // -- Collect curation fees --
            // Only if the subgraph deployment is curated
            curationFees = _collectCurationFees(subgraphDeploymentID, queryFees, __DEPRECATED_curationPercentage);
            queryFees = queryFees - curationFees;

            // -- Process rebate reward --
            // Using accumulated fees and subtracting previously distributed rebates
            // allows for multiple vouchers to be collected while following the rebate formula
            alloc.collectedFees = alloc.collectedFees + queryFees;

            // No rebates if indexer has no stake or if lambda is zero
            uint256 newRebates = (alloc.tokens == 0 || __DEPRECATED_lambdaNumerator == 0)
                ? 0
                : ExponentialRebates.exponentialRebates(
                    alloc.collectedFees,
                    alloc.tokens,
                    __DEPRECATED_alphaNumerator,
                    __DEPRECATED_alphaDenominator,
                    __DEPRECATED_lambdaNumerator,
                    __DEPRECATED_lambdaDenominator
                );

            //  -- Ensure rebates to distribute are within bounds --
            // Indexers can become under or over rebated if rebate parameters (alpha, lambda)
            // change between successive collect calls for the same allocation

            // Ensure rebates to distribute are not negative (indexer is over-rebated)
            queryRebates = MathUtils.diffOrZero(newRebates, alloc.distributedRebates);

            // Ensure rebates to distribute are not greater than available (indexer is under-rebated)
            queryRebates = MathUtils.min(queryRebates, queryFees);

            // -- Burn rebates remanent --
            _graphToken().burnTokens(queryFees - queryRebates);

            // -- Distribute rebates --
            if (queryRebates > 0) {
                alloc.distributedRebates = alloc.distributedRebates + queryRebates;

                // -- Collect delegation rewards into the delegation pool --
                delegationRewards = _collectDelegationQueryRewards(alloc.indexer, queryRebates);
                queryRebates = queryRebates - delegationRewards;

                // -- Transfer or restake rebates --
                _sendRewards(queryRebates, alloc.indexer, __DEPRECATED_rewardsDestination[alloc.indexer] == address(0));
            }
        }

        emit RebateCollected(
            msg.sender,
            alloc.indexer,
            subgraphDeploymentID,
            allocationID,
            _graphEpochManager().currentEpoch(),
            tokens,
            protocolTax,
            curationFees,
            queryFees,
            queryRebates,
            delegationRewards
        );
    }

    /**
     * @notice Return if allocationID is used.
     * @dev TODO: Remove after Horizon transition period
     * @param allocationID Address used as signer by the indexer for an allocation
     * @return True if allocationID already used
     */
    function isAllocation(address allocationID) external view override returns (bool) {
        return _getAllocationState(allocationID) != AllocationState.Null;
    }

    /**
     * @notice Return the allocation by ID.
     * @dev TODO: Remove after Horizon transition period
     * @param allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address allocationID) external view override returns (Allocation memory) {
        return __DEPRECATED_allocations[allocationID];
    }

    /**
     * @notice Return allocation data by ID.
     * @dev To be called by the Rewards Manager to calculate rewards issuance.
     * @dev TODO: Remove after Horizon transition period
     * @param allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocationData(
        address allocationID
    ) external view override returns (address, bytes32, uint256, uint256) {
        Allocation memory allo = __DEPRECATED_allocations[allocationID];
        return (allo.indexer, allo.subgraphDeploymentID, allo.tokens, allo.accRewardsPerAllocatedToken);
    }

    /**
     * @notice Return the current state of an allocation
     * @dev TODO: Remove after Horizon transition period
     * @param allocationID Allocation identifier
     * @return AllocationState enum with the state of the allocation
     */
    function getAllocationState(address allocationID) external view override returns (AllocationState) {
        return _getAllocationState(allocationID);
    }

    /**
     * @notice Return the total amount of tokens allocated to subgraph.
     * @param subgraphDeploymentID Deployment ID for the subgraph
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 subgraphDeploymentID) external view override returns (uint256) {
        return __DEPRECATED_subgraphAllocations[subgraphDeploymentID];
    }

    /**
     * @notice Get the total amount of tokens staked by the indexer.
     * @param indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address indexer) external view override returns (uint256) {
        return _serviceProviders[indexer].tokensStaked;
    }

    /**
     * @notice Getter that returns if an indexer has any stake.
     * @param indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address indexer) external view override returns (bool) {
        return _serviceProviders[indexer].tokensStaked > 0;
    }

    /**
     * @notice (Legacy) Return true if operator is allowed for the service provider on the subgraph data service.
     * @dev TODO: Delete after the transition period
     * @param operator Address of the operator
     * @param serviceProvider Address of the service provider
     * @return True if operator is allowed for indexer, false otherwise
     */
    function isOperator(address operator, address serviceProvider) public view override returns (bool) {
        return _legacyOperatorAuth[serviceProvider][operator];
    }

    /**
     * @dev Receive an Indexer's stake from L1.
     * The specified amount is added to the indexer's stake; the indexer's
     * address is specified in the _indexerData struct.
     * @param _tokens Amount of tokens that were transferred
     * @param _indexerData struct containing the indexer's address
     */
    function _receiveIndexerStake(
        uint256 _tokens,
        IL2StakingTypes.ReceiveIndexerStakeData memory _indexerData
    ) internal {
        address indexer = _indexerData.indexer;
        // Deposit tokens into the indexer stake
        _stake(indexer, _tokens);
    }

    /**
     * @dev Receive a Delegator's delegation from L1.
     * The specified amount is added to the delegator's delegation; the delegator's
     * address and the indexer's address are specified in the _delegationData struct.
     * Note that no delegation tax is applied here.
     * @param _tokens Amount of tokens that were transferred
     * @param _delegationData struct containing the delegator's address and the indexer's address
     */
    function _receiveDelegation(
        uint256 _tokens,
        IL2StakingTypes.ReceiveDelegationData memory _delegationData
    ) internal {
        // Get the delegation pool of the indexer
        IHorizonStakingTypes.DelegationPoolInternal storage pool = _legacyDelegationPools[_delegationData.indexer];
        IHorizonStakingTypes.Delegation storage delegation = pool.delegators[_delegationData.delegator];

        // Calculate shares to issue (without applying any delegation tax)
        uint256 shares = (pool.tokens == 0) ? _tokens : ((_tokens * pool.shares) / pool.tokens);

        if (shares == 0 || _tokens < MINIMUM_DELEGATION) {
            // If no shares would be issued (probably a rounding issue or attack),
            // or if the amount is under the minimum delegation (which could be part of a rounding attack),
            // return the tokens to the delegator
            _graphToken().transfer(_delegationData.delegator, _tokens);
            emit TransferredDelegationReturnedToDelegator(_delegationData.indexer, _delegationData.delegator, _tokens);
        } else {
            // Update the delegation pool
            pool.tokens = pool.tokens + _tokens;
            pool.shares = pool.shares + shares;

            // Update the individual delegation
            delegation.shares = delegation.shares + shares;

            emit StakeDelegated(_delegationData.indexer, _delegationData.delegator, _tokens, shares);
        }
    }

    /**
     * @dev Collect tax to burn for an amount of tokens.
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @param _percentage Percentage of tokens to burn as tax
     * @return Amount of tax charged
     */
    function _collectTax(uint256 _tokens, uint256 _percentage) private returns (uint256) {
        uint256 tax = _tokens.mulPPMRoundUp(_percentage);
        _graphToken().burnTokens(tax); // Burn tax if any
        return tax;
    }

    /**
     * @dev Triggers an update of rewards due to a change in allocations.
     * @param _subgraphDeploymentID Subgraph deployment updated
     * @return Accumulated rewards per allocated token for the subgraph deployment
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) private returns (uint256) {
        return _graphRewardsManager().onSubgraphAllocationUpdate(_subgraphDeploymentID);
    }

    /**
     * @dev Assign rewards for the closed allocation to indexer and delegators.
     * @param _allocationID Allocation
     * @param _indexer Address of the indexer that did the allocation
     */
    function _distributeRewards(address _allocationID, address _indexer) private {
        // Automatically triggers update of rewards snapshot as allocation will change
        // after this call. Take rewards mint tokens for the Staking contract to distribute
        // between indexer and delegators
        uint256 totalRewards = _graphRewardsManager().takeRewards(_allocationID);
        if (totalRewards == 0) {
            return;
        }

        // Calculate delegation rewards and add them to the delegation pool
        uint256 delegationRewards = _collectDelegationIndexingRewards(_indexer, totalRewards);
        uint256 indexerRewards = totalRewards - delegationRewards;

        // Send the indexer rewards
        _sendRewards(indexerRewards, _indexer, __DEPRECATED_rewardsDestination[_indexer] == address(0));
    }

    /**
     * @dev Send rewards to the appropriate destination.
     * @param _tokens Number of rewards tokens
     * @param _beneficiary Address of the beneficiary of rewards
     * @param _restake Whether to restake or not
     */
    function _sendRewards(uint256 _tokens, address _beneficiary, bool _restake) private {
        if (_tokens == 0) return;

        if (_restake) {
            // Restake to place fees into the indexer stake
            _stake(_beneficiary, _tokens);
        } else {
            // Transfer funds to the beneficiary's designated rewards destination if set
            address destination = __DEPRECATED_rewardsDestination[_beneficiary];
            _graphToken().pushTokens(destination == address(0) ? _beneficiary : destination, _tokens);
        }
    }

    /**
     * @dev Close an allocation and free the staked tokens.
     * @param _allocationID The allocation identifier
     * @param _poi Proof of indexing submitted for the allocated period
     */
    function _closeAllocation(address _allocationID, bytes32 _poi) private {
        // Allocation must exist and be active
        AllocationState allocState = _getAllocationState(_allocationID);
        require(allocState == AllocationState.Active, "!active");

        // Get allocation
        Allocation memory alloc = __DEPRECATED_allocations[_allocationID];

        // Validate that an allocation cannot be closed before one epoch
        alloc.closedAtEpoch = _graphEpochManager().currentEpoch();
        uint256 epochs = MathUtils.diffOrZero(alloc.closedAtEpoch, alloc.createdAtEpoch);

        // Indexer or operator can close an allocation
        // Anyone is allowed to close ONLY under two concurrent conditions
        // - After maxAllocationEpochs passed
        // - When the allocation is for non-zero amount of tokens
        bool isIndexer = isOperator(alloc.indexer, SUBGRAPH_DATA_SERVICE_ADDRESS);
        if (epochs <= __DEPRECATED_maxAllocationEpochs || alloc.tokens == 0) {
            require(isIndexer, "!auth");
        }

        // Close the allocation
        __DEPRECATED_allocations[_allocationID].closedAtEpoch = alloc.closedAtEpoch;

        // -- Rewards Distribution --

        // Process non-zero-allocation rewards tracking
        if (alloc.tokens > 0) {
            // Distribute rewards if proof of indexing was presented by the indexer or operator
            if (isIndexer && _poi != 0) {
                _distributeRewards(_allocationID, alloc.indexer);
            } else {
                _updateRewards(alloc.subgraphDeploymentID);
            }

            // Free allocated tokens from use
            _serviceProviders[alloc.indexer].__DEPRECATED_tokensAllocated =
                _serviceProviders[alloc.indexer].__DEPRECATED_tokensAllocated -
                alloc.tokens;

            // Track total allocations per subgraph
            // Used for rewards calculations
            __DEPRECATED_subgraphAllocations[alloc.subgraphDeploymentID] =
                __DEPRECATED_subgraphAllocations[alloc.subgraphDeploymentID] -
                alloc.tokens;
        }

        emit AllocationClosed(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            alloc.closedAtEpoch,
            alloc.tokens,
            _allocationID,
            msg.sender,
            _poi,
            !isIndexer
        );
    }

    /**
     * @dev Collect the delegation rewards for query fees.
     * This function will assign the collected fees to the delegation pool.
     * @param _indexer Indexer to which the tokens to distribute are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of delegation rewards
     */
    function _collectDelegationQueryRewards(address _indexer, uint256 _tokens) private returns (uint256) {
        uint256 delegationRewards = 0;
        IHorizonStakingTypes.DelegationPoolInternal storage pool = _legacyDelegationPools[_indexer];
        if (pool.tokens > 0 && uint256(pool.__DEPRECATED_queryFeeCut).isValidPPM()) {
            uint256 indexerCut = uint256(pool.__DEPRECATED_queryFeeCut).mulPPM(_tokens);
            delegationRewards = _tokens - indexerCut;
            pool.tokens = pool.tokens + delegationRewards;
        }
        return delegationRewards;
    }

    /**
     * @dev Collect the delegation rewards for indexing.
     * This function will assign the collected fees to the delegation pool.
     * @param _indexer Indexer to which the tokens to distribute are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of delegation rewards
     */
    function _collectDelegationIndexingRewards(address _indexer, uint256 _tokens) private returns (uint256) {
        uint256 delegationRewards = 0;
        IHorizonStakingTypes.DelegationPoolInternal storage pool = _legacyDelegationPools[_indexer];
        if (pool.tokens > 0 && uint256(pool.__DEPRECATED_indexingRewardCut).isValidPPM()) {
            uint256 indexerCut = uint256(pool.__DEPRECATED_indexingRewardCut).mulPPM(_tokens);
            delegationRewards = _tokens - indexerCut;
            pool.tokens = pool.tokens + delegationRewards;
        }
        return delegationRewards;
    }

    /**
     * @dev Collect the curation fees for a subgraph deployment from an amount of tokens.
     * This function transfer curation fees to the Curation contract by calling Curation.collect
     * @param _subgraphDeploymentID Subgraph deployment to which the curation fees are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @param _curationCut Percentage of tokens to collect as fees
     * @return Amount of curation fees
     */
    function _collectCurationFees(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        uint256 _curationCut
    ) private returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }

        ICuration curation = _graphCuration();
        bool isCurationEnabled = _curationCut > 0 && address(curation) != address(0);

        if (isCurationEnabled && curation.isCurated(_subgraphDeploymentID)) {
            uint256 curationFees = _tokens.mulPPMRoundUp(_curationCut);
            if (curationFees > 0) {
                // Transfer and call collect()
                // This function transfer tokens to a trusted protocol contracts
                // Then we call collect() to do the transfer bookeeping
                _graphRewardsManager().onSubgraphSignalUpdate(_subgraphDeploymentID);
                _graphToken().pushTokens(address(curation), curationFees);
                curation.collect(_subgraphDeploymentID, curationFees);
            }
            return curationFees;
        }
        return 0;
    }

    /**
     * @dev Return the current state of an allocation
     * @param _allocationID Allocation identifier
     * @return AllocationState enum with the state of the allocation
     */
    function _getAllocationState(address _allocationID) private view returns (AllocationState) {
        Allocation storage alloc = __DEPRECATED_allocations[_allocationID];

        if (alloc.indexer == address(0)) {
            return AllocationState.Null;
        }

        if (alloc.createdAtEpoch != 0 && alloc.closedAtEpoch == 0) {
            return AllocationState.Active;
        }

        return AllocationState.Closed;
    }
}
