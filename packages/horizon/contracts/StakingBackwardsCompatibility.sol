// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { Multicall } from "@graphprotocol/contracts/contracts/base/Multicall.sol";
import { GraphUpgradeable } from "@graphprotocol/contracts/contracts/upgrades/GraphUpgradeable.sol";
import { TokenUtils } from "./utils/TokenUtils.sol";
import { IGraphToken } from "./IGraphToken.sol";
import { HorizonStakingV1Storage } from "./HorizonStakingStorage.sol";
import { MathUtils } from "./utils/MathUtils.sol";
import { Managed } from "./Managed.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { ExponentialRebates } from "./utils/ExponentialRebates.sol";
import { IStakingBackwardsCompatibility } from "./IStakingBackwardsCompatibility.sol";

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
abstract contract StakingBackwardsCompatibility is
    HorizonStakingV1Storage,
    GraphUpgradeable,
    Multicall,
    IStakingBackwardsCompatibility
{
    /// @dev 100% in parts per million
    uint32 internal constant MAX_PPM = 1000000;

    address public immutable SUBGRAPH_DATA_SERVICE_ADDRESS;

    address public immutable EXPONENTIAL_REBATES_ADDRESS;

    constructor(
        address _controller,
        address _subgraphDataServiceAddress,
        address _exponentialRebatesAddress
    ) Managed(_controller) {
        SUBGRAPH_DATA_SERVICE_ADDRESS = _subgraphDataServiceAddress;
        EXPONENTIAL_REBATES_ADDRESS = _exponentialRebatesAddress;
    }

    /**
     * @notice Set the address of the counterpart (L1 or L2) staking contract.
     * @dev This function can only be called by the governor.
     * TODO: Remove after L2 transition period
     * @param _counterpart Address of the counterpart staking contract in the other chain, without any aliasing.
     */
    function setCounterpartStakingAddress(address _counterpart) external override onlyGovernor {
        counterpartStakingAddress = _counterpart;
        emit ParameterUpdated("counterpartStakingAddress");
    }

    /**
     * @notice Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out of rewards set _poi to 0x0
     * @dev TODO: Remove after Horizon transition period
     * @param _allocationID The allocation identifier
     * @param _poi Proof of indexing submitted for the allocated period
     */
    function closeAllocation(address _allocationID, bytes32 _poi) external override notPaused {
        _closeAllocation(_allocationID, _poi);
    }

    /**
     * @dev Collect and rebate query fees from state channels to the indexer
     * To avoid reverting on the withdrawal from channel flow this function will accept calls with zero tokens.
     * We use an exponential rebate formula to calculate the amount of tokens to rebate to the indexer.
     * This implementation allows collecting multiple times on the same allocation, keeping track of the
     * total amount rebated, the total amount collected and compensating the indexer for the difference.
     * TODO: Remove after Horizon transition period
     * @param _tokens Amount of tokens to collect
     * @param _allocationID Allocation where the tokens will be assigned
     */
    function collect(uint256 _tokens, address _allocationID) external override {
        // Allocation identifier validation
        require(_allocationID != address(0), "!alloc");

        // Allocation must exist
        AllocationState allocState = _getAllocationState(_allocationID);
        require(allocState != AllocationState.Null, "!collect");

        // If the query fees are zero, we don't want to revert
        // but we also don't need to do anything, so just return
        if (_tokens == 0) {
            return;
        }

        Allocation storage alloc = __DEPRECATED_allocations[_allocationID];
        bytes32 subgraphDeploymentID = alloc.subgraphDeploymentID;

        uint256 queryFees = _tokens; // Tokens collected from the channel
        uint256 protocolTax = 0; // Tokens burnt as protocol tax
        uint256 curationFees = 0; // Tokens distributed to curators as curation fees
        uint256 queryRebates = 0; // Tokens to distribute to indexer
        uint256 delegationRewards = 0; // Tokens to distribute to delegators

        {
            // -- Pull tokens from the sender --
            IGraphToken graphToken = _graphToken();
            TokenUtils.pullTokens(graphToken, msg.sender, queryFees);

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
                : ExponentialRebates(EXPONENTIAL_REBATES_ADDRESS).exponentialRebates(
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
            TokenUtils.burnTokens(graphToken, queryFees - queryRebates);

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
            _allocationID,
            _epochManager().currentEpoch(),
            _tokens,
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
     * @param _allocationID Address used as signer by the indexer for an allocation
     * @return True if allocationID already used
     */
    function isAllocation(address _allocationID) external view override returns (bool) {
        return _getAllocationState(_allocationID) != AllocationState.Null;
    }

    /**
     * @notice Return the allocation by ID.
     * @dev TODO: Remove after Horizon transition period
     * @param _allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address _allocationID) external view override returns (Allocation memory) {
        return __DEPRECATED_allocations[_allocationID];
    }

    /**
     * @notice Return the current state of an allocation
     * @dev TODO: Remove after Horizon transition period
     * @param _allocationID Allocation identifier
     * @return AllocationState enum with the state of the allocation
     */
    function getAllocationState(address _allocationID) external view override returns (AllocationState) {
        return _getAllocationState(_allocationID);
    }

    /**
     * @notice Return the total amount of tokens allocated to subgraph.
     * @param _subgraphDeploymentID Deployment ID for the subgraph
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 _subgraphDeploymentID) external view override returns (uint256) {
        return __DEPRECATED_subgraphAllocations[_subgraphDeploymentID];
    }

    /**
     * @notice (Legacy) Return true if operator is allowed for the service provider on the subgraph data service.
     * @dev TODO: Delete after the transition period
     * @param _operator Address of the operator
     * @param _serviceProvider Address of the service provider
     * @return True if operator is allowed for indexer, false otherwise
     */
    function isOperator(address _operator, address _serviceProvider) public view override returns (bool) {
        return legacyOperatorAuth[_serviceProvider][_operator];
    }

    /**
     * @notice Get the total amount of tokens staked by the indexer.
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address _indexer) external view override returns (uint256) {
        return serviceProviders[_indexer].tokensStaked;
    }

    /**
     * @notice Getter that returns if an indexer has any stake.
     * @param _indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address _indexer) external view override returns (bool) {
        return serviceProviders[_indexer].tokensStaked > 0;
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
        alloc.closedAtEpoch = _epochManager().currentEpoch();
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
            serviceProviders[alloc.indexer].__DEPRECATED_tokensAllocated =
                serviceProviders[alloc.indexer].__DEPRECATED_tokensAllocated -
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
        DelegationPoolInternal storage pool = legacyDelegationPools[_indexer];
        if (pool.tokens > 0 && pool.__DEPRECATED_queryFeeCut < MAX_PPM) {
            uint256 indexerCut = (uint256(pool.__DEPRECATED_queryFeeCut) * _tokens) / MAX_PPM;
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
        DelegationPoolInternal storage pool = legacyDelegationPools[_indexer];
        if (pool.tokens > 0 && pool.__DEPRECATED_indexingRewardCut < MAX_PPM) {
            uint256 indexerCut = (uint256(pool.__DEPRECATED_indexingRewardCut) * _tokens) / MAX_PPM;
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
     * @param _curationPercentage Percentage of tokens to collect as fees
     * @return Amount of curation fees
     */
    function _collectCurationFees(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        uint256 _curationPercentage
    ) private returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }

        ICuration curation = _curation();
        bool isCurationEnabled = _curationPercentage > 0 && address(curation) != address(0);

        if (isCurationEnabled && curation.isCurated(_subgraphDeploymentID)) {
            // Calculate the tokens after curation fees first, and subtact that,
            // to prevent curation fees from rounding down to zero
            uint256 tokensAfterCurationFees = ((uint256(MAX_PPM) - _curationPercentage) * _tokens) / MAX_PPM;
            uint256 curationFees = _tokens - tokensAfterCurationFees;
            if (curationFees > 0) {
                // Transfer and call collect()
                // This function transfer tokens to a trusted protocol contracts
                // Then we call collect() to do the transfer bookeeping
                _rewardsManager().onSubgraphSignalUpdate(_subgraphDeploymentID);
                TokenUtils.pushTokens(_graphToken(), address(curation), curationFees);
                curation.collect(_subgraphDeploymentID, curationFees);
            }
            return curationFees;
        }
        return 0;
    }

    /**
     * @dev Collect tax to burn for an amount of tokens.
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @param _percentage Percentage of tokens to burn as tax
     * @return Amount of tax charged
     */
    function _collectTax(uint256 _tokens, uint256 _percentage) private returns (uint256) {
        // Calculate tokens after tax first, and subtract that,
        // to prevent the tax from rounding down to zero
        uint256 tokensAfterTax = ((uint256(MAX_PPM) - _percentage) * _tokens) / MAX_PPM;
        uint256 tax = _tokens - tokensAfterTax;
        TokenUtils.burnTokens(_graphToken(), tax); // Burn tax if any
        return tax;
    }

    /**
     * @dev Triggers an update of rewards due to a change in allocations.
     * @param _subgraphDeploymentID Subgraph deployment updated
     * @return Accumulated rewards per allocated token for the subgraph deployment
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) private returns (uint256) {
        IRewardsManager rewardsManager = _rewardsManager();
        if (address(rewardsManager) == address(0)) {
            return 0;
        }
        return rewardsManager.onSubgraphAllocationUpdate(_subgraphDeploymentID);
    }

    /**
     * @dev Assign rewards for the closed allocation to indexer and delegators.
     * @param _allocationID Allocation
     * @param _indexer Address of the indexer that did the allocation
     */
    function _distributeRewards(address _allocationID, address _indexer) private {
        IRewardsManager rewardsManager = _rewardsManager();
        if (address(rewardsManager) == address(0)) {
            return;
        }

        // Automatically triggers update of rewards snapshot as allocation will change
        // after this call. Take rewards mint tokens for the Staking contract to distribute
        // between indexer and delegators
        uint256 totalRewards = rewardsManager.takeRewards(_allocationID);
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
     * @param _amount Number of rewards tokens
     * @param _beneficiary Address of the beneficiary of rewards
     * @param _restake Whether to restake or not
     */
    function _sendRewards(uint256 _amount, address _beneficiary, bool _restake) private {
        if (_amount == 0) return;

        if (_restake) {
            // Restake to place fees into the indexer stake
            _stake(_beneficiary, _amount);
        } else {
            // Transfer funds to the beneficiary's designated rewards destination if set
            address destination = __DEPRECATED_rewardsDestination[_beneficiary];
            TokenUtils.pushTokens(_graphToken(), destination == address(0) ? _beneficiary : destination, _amount);
        }
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

    /**
     * @dev Stake tokens on the service provider.
     * TODO: Move to HorizonStaking after the transition period
     * @param _serviceProvider Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _serviceProvider, uint256 _tokens) internal {
        // Deposit tokens into the indexer stake
        serviceProviders[_serviceProvider].tokensStaked = serviceProviders[_serviceProvider].tokensStaked + _tokens;

        emit StakeDeposited(_serviceProvider, _tokens);
    }

    function _graphToken() internal view returns (IGraphToken) {
        return IGraphToken(GRAPH_TOKEN);
    }

    function _curation() internal view returns (ICuration) {
        return ICuration(CURATION);
    }

    function _rewardsManager() internal view returns (IRewardsManager) {
        return IRewardsManager(REWARDS_MANAGER);
    }

    function _epochManager() internal view returns (IEpochManager) {
        return IEpochManager(EPOCH_MANAGER);
    }
}
