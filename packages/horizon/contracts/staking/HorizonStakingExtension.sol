// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStakingExtension } from "../interfaces/internal/IHorizonStakingExtension.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { MathUtils } from "../libraries/MathUtils.sol";
import { ExponentialRebates } from "./libraries/ExponentialRebates.sol";
import { PPMMath } from "../libraries/PPMMath.sol";

import { HorizonStakingBase } from "./HorizonStakingBase.sol";

/**
 * @title Horizon Staking extension contract
 * @notice The {HorizonStakingExtension} contract implements the legacy functionality required to support the transition
 * to the Horizon Staking contract. It allows indexers to close allocations and collect pending query fees, but it
 * does not allow for the creation of new allocations. This should allow indexers to migrate to a subgraph data service
 * without losing rewards or having service interruptions.
 * @dev TODO: Once the transition period passes this contract can be removed (note that an upgrade to the RewardsManager
 * will also be required). It's expected the transition period to last for a full allocation cycle (28 epochs).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract HorizonStakingExtension is HorizonStakingBase, IHorizonStakingExtension {
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;

    /**
     * @dev Checks that the sender is the L2GraphTokenGateway as configured on the Controller.
     */
    modifier onlyL2Gateway() {
        require(msg.sender == address(_graphTokenGateway()), "ONLY_GATEWAY");
        _;
    }

    /**
     * @dev Check if the caller is the slasher.
     */
    modifier onlySlasher() {
        require(__DEPRECATED_slashers[msg.sender] == true, "!slasher");
        _;
    }

    /**
     * @dev The staking contract is upgradeable however we still use the constructor to set
     * a few immutable variables.
     * @param controller The address of the Graph controller contract.
     * @param subgraphDataServiceAddress The address of the subgraph data service.
     */
    constructor(
        address controller,
        address subgraphDataServiceAddress
    ) HorizonStakingBase(controller, subgraphDataServiceAddress) {}

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
    function collect(uint256 tokens, address allocationID) external override notPaused {
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
     * @dev Note that the accRewardsPending field is not used and will always be zero.
     * @param allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocationData(
        address allocationID
    ) external view override returns (address, bytes32, uint256, uint256, uint256) {
        Allocation memory allo = __DEPRECATED_allocations[allocationID];
        return (allo.indexer, allo.subgraphDeploymentID, allo.tokens, allo.accRewardsPerAllocatedToken, 0);
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
     * @notice Return true if allocation is active.
     * @param allocationID Allocation identifier
     * @return True if allocation is active
     */
    function isActiveAllocation(address allocationID) external view override returns (bool) {
        return _getAllocationState(allocationID) == AllocationState.Active;
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
     * @notice Return the time in blocks to unstake
     * Deprecated, now enforced by each data service (verifier)
     * @return Thawing period in blocks
     */
    // solhint-disable-next-line func-name-mixedcase
    function __DEPRECATED_getThawingPeriod() external view returns (uint64) {
        return __DEPRECATED_thawingPeriod;
    }

    function legacySlash(
        address indexer,
        uint256 tokens,
        uint256 reward,
        address beneficiary
    ) external override onlySlasher notPaused {
        ServiceProviderInternal storage indexerStake = _serviceProviders[indexer];

        // Only able to slash a non-zero number of tokens
        require(tokens > 0, "!tokens");

        // Rewards comes from tokens slashed balance
        require(tokens >= reward, "rewards>slash");

        // Cannot slash stake of an indexer without any or enough stake
        require(indexerStake.tokensStaked > 0, "!stake");
        require(tokens <= indexerStake.tokensStaked, "slash>stake");

        // Validate beneficiary of slashed tokens
        require(beneficiary != address(0), "!beneficiary");

        // Slashing more tokens than freely available (over allocation condition)
        // Unlock locked tokens to avoid the indexer to withdraw them
        uint256 tokensUsed = indexerStake.__DEPRECATED_tokensAllocated + indexerStake.__DEPRECATED_tokensLocked;
        uint256 tokensAvailable = tokensUsed > indexerStake.tokensStaked ? 0 : indexerStake.tokensStaked - tokensUsed;
        if (tokens > tokensAvailable && indexerStake.__DEPRECATED_tokensLocked > 0) {
            uint256 tokensOverAllocated = tokens - tokensAvailable;
            uint256 tokensToUnlock = MathUtils.min(tokensOverAllocated, indexerStake.__DEPRECATED_tokensLocked);
            indexerStake.__DEPRECATED_tokensLocked = indexerStake.__DEPRECATED_tokensLocked - tokensToUnlock;
            if (indexerStake.__DEPRECATED_tokensLocked == 0) {
                indexerStake.__DEPRECATED_tokensLockedUntil = 0;
            }
        }

        // Remove tokens to slash from the stake
        indexerStake.tokensStaked = indexerStake.tokensStaked - tokens;

        // -- Interactions --

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        _graphToken().burnTokens(tokens - reward);

        // Give the beneficiary a reward for slashing
        _graphToken().pushTokens(beneficiary, reward);

        emit StakeSlashed(indexer, tokens, reward, beneficiary);
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
        bool isIndexerOrOperator = msg.sender == alloc.indexer || isOperator(msg.sender, alloc.indexer);
        if (epochs <= __DEPRECATED_maxAllocationEpochs || alloc.tokens == 0) {
            require(isIndexerOrOperator, "!auth");
        }

        // Close the allocation
        __DEPRECATED_allocations[_allocationID].closedAtEpoch = alloc.closedAtEpoch;

        // -- Rewards Distribution --

        // Process non-zero-allocation rewards tracking
        if (alloc.tokens > 0) {
            // Distribute rewards if proof of indexing was presented by the indexer or operator
            if (isIndexerOrOperator && _poi != 0) {
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
            !isIndexerOrOperator
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
        DelegationPoolInternal storage pool = _legacyDelegationPools[_indexer];
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
        DelegationPoolInternal storage pool = _legacyDelegationPools[_indexer];
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
                // Then we call collect() to do the transfer Bookkeeping
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
