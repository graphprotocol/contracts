// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

import { Multicall } from "../base/Multicall.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { IGraphToken } from "../token/IGraphToken.sol";
import { IStakingBase } from "./IStakingBase.sol";
import { StakingV4Storage } from "./StakingStorage.sol";
import { MathUtils } from "./libs/MathUtils.sol";
import { Stakes } from "./libs/Stakes.sol";
import { Managed } from "../governance/Managed.sol";
import { ICuration } from "../curation/ICuration.sol";
import { IRewardsManager } from "../rewards/IRewardsManager.sol";
import { StakingExtension } from "./StakingExtension.sol";
import { LibExponential } from "./libs/Exponential.sol";

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
abstract contract Staking is StakingV4Storage, GraphUpgradeable, IStakingBase, Multicall {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;

    /// @dev 100% in parts per million
    uint32 internal constant MAX_PPM = 1000000;

    // -- Events are declared in IStakingBase -- //

    /**
     * @notice Delegates the current call to the StakingExtension implementation.
     * @dev This function does not return to its internal call site, it will return directly to the
     * external caller.
     */
    // solhint-disable-next-line payable-fallback, no-complex-fallback
    fallback() external {
        require(_implementation() != address(0), "only through proxy");
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // (a) get free memory pointer
            let ptr := mload(0x40)

            // (b) get address of the implementation
            // CAREFUL here: this only works because extensionImpl is the first variable in this slot
            // (otherwise we may have to apply an offset)
            let impl := and(sload(extensionImpl.slot), 0xffffffffffffffffffffffffffffffffffffffff)

            // (1) copy incoming call data
            calldatacopy(ptr, 0, calldatasize())

            // (2) forward call to logic contract
            let result := delegatecall(gas(), impl, ptr, calldatasize(), 0, 0)
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

    /**
     * @notice Initialize this contract.
     * @param _controller Address of the controller that manages this contract
     * @param _minimumIndexerStake Minimum amount of tokens that an indexer must stake
     * @param _thawingPeriod Number of epochs that tokens get locked after unstaking
     * @param _protocolPercentage Percentage of query fees that are burned as protocol fee (in PPM)
     * @param _curationPercentage Percentage of query fees that are given to curators (in PPM)
     * @param _maxAllocationEpochs The maximum number of epochs that an allocation can be active
     * @param _delegationUnbondingPeriod The period in epochs that tokens get locked after undelegating
     * @param _delegationRatio The ratio between an indexer's own stake and the delegation they can use
     * @param _rebatesParameters Alpha and lambda parameters for rebates function
     * @param _extensionImpl Address of the StakingExtension implementation
     */
    function initialize(
        address _controller,
        uint256 _minimumIndexerStake,
        uint32 _thawingPeriod,
        uint32 _protocolPercentage,
        uint32 _curationPercentage,
        uint32 _maxAllocationEpochs,
        uint32 _delegationUnbondingPeriod,
        uint32 _delegationRatio,
        RebatesParameters calldata _rebatesParameters,
        address _extensionImpl
    ) external override onlyImpl {
        Managed._initialize(_controller);

        // Settings

        _setMinimumIndexerStake(_minimumIndexerStake);
        _setThawingPeriod(_thawingPeriod);

        _setProtocolPercentage(_protocolPercentage);
        _setCurationPercentage(_curationPercentage);

        _setMaxAllocationEpochs(_maxAllocationEpochs);

        _setRebateParameters(
            _rebatesParameters.alphaNumerator,
            _rebatesParameters.alphaDenominator,
            _rebatesParameters.lambdaNumerator,
            _rebatesParameters.lambdaDenominator
        );

        extensionImpl = _extensionImpl;

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = extensionImpl.delegatecall(
            abi.encodeWithSelector(
                StakingExtension.initialize.selector,
                _delegationUnbondingPeriod,
                0,
                _delegationRatio,
                0
            )
        );
        require(success, "Extension init failed");
        emit ExtensionImplementationSet(_extensionImpl);
    }

    /**
     * @notice Set the address of the StakingExtension implementation.
     * @dev This function can only be called by the governor.
     * @param _extensionImpl Address of the StakingExtension implementation
     */
    function setExtensionImpl(address _extensionImpl) external override onlyGovernor {
        extensionImpl = _extensionImpl;
        emit ExtensionImplementationSet(_extensionImpl);
    }

    /**
     * @notice Set the address of the counterpart (L1 or L2) staking contract.
     * @dev This function can only be called by the governor.
     * @param _counterpart Address of the counterpart staking contract in the other chain, without any aliasing.
     */
    function setCounterpartStakingAddress(address _counterpart) external override onlyGovernor {
        counterpartStakingAddress = _counterpart;
        emit ParameterUpdated("counterpartStakingAddress");
    }

    /**
     * @notice Set the minimum stake required to be an indexer.
     * @param _minimumIndexerStake Minimum indexer stake
     */
    function setMinimumIndexerStake(uint256 _minimumIndexerStake) external override onlyGovernor {
        _setMinimumIndexerStake(_minimumIndexerStake);
    }

    /**
     * @notice Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function setThawingPeriod(uint32 _thawingPeriod) external override onlyGovernor {
        _setThawingPeriod(_thawingPeriod);
    }

    /**
     * @notice Set the curation percentage of query fees sent to curators.
     * @param _percentage Percentage of query fees sent to curators
     */
    function setCurationPercentage(uint32 _percentage) external override onlyGovernor {
        _setCurationPercentage(_percentage);
    }

    /**
     * @notice Set a protocol percentage to burn when collecting query fees.
     * @param _percentage Percentage of query fees to burn as protocol fee
     */
    function setProtocolPercentage(uint32 _percentage) external override onlyGovernor {
        _setProtocolPercentage(_percentage);
    }

    /**
     * @notice Set the max time allowed for indexers to allocate on a subgraph
     * before others are allowed to close the allocation.
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function setMaxAllocationEpochs(uint32 _maxAllocationEpochs) external override onlyGovernor {
        _setMaxAllocationEpochs(_maxAllocationEpochs);
    }

    /**
     * @dev Set the rebate parameters.
     * @param _alphaNumerator Numerator of `alpha` in the rebates function
     * @param _alphaDenominator Denominator of `alpha` in the rebates function
     * @param _lambdaNumerator Numerator of `lambda` in the rebates function
     * @param _lambdaDenominator Denominator of `lambda` in the rebates function
     */
    function setRebateParameters(
        uint32 _alphaNumerator,
        uint32 _alphaDenominator,
        uint32 _lambdaNumerator,
        uint32 _lambdaDenominator
    ) external override onlyGovernor {
        _setRebateParameters(_alphaNumerator, _alphaDenominator, _lambdaNumerator, _lambdaDenominator);
    }

    /**
     * @notice Authorize or unauthorize an address to be an operator for the caller.
     * @param _operator Address to authorize or unauthorize
     * @param _allowed Whether the operator is authorized or not
     */
    function setOperator(address _operator, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        __operatorAuth[msg.sender][_operator] = _allowed;
        emit SetOperator(msg.sender, _operator, _allowed);
    }

    /**
     * @notice Deposit tokens on the indexer's stake.
     * The amount staked must be over the minimumIndexerStake.
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external override {
        stakeTo(msg.sender, _tokens);
    }

    /**
     * @notice Unstake tokens from the indexer stake, lock them until the thawing period expires.
     * @dev NOTE: The function accepts an amount greater than the currently staked tokens.
     * If that happens, it will try to unstake the max amount of tokens it can.
     * The reason for this behaviour is to avoid time conditions while the transaction
     * is in flight.
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external override notPartialPaused {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = __stakes[indexer];

        require(indexerStake.tokensStaked > 0, "!stake");

        // Tokens to lock is capped to the available tokens
        uint256 tokensToLock = MathUtils.min(indexerStake.tokensAvailable(), _tokens);
        require(tokensToLock > 0, "!stake-avail");

        // Ensure minimum stake
        uint256 newStake = indexerStake.tokensSecureStake().sub(tokensToLock);
        require(newStake == 0 || newStake >= __minimumIndexerStake, "!minimumIndexerStake");

        // Before locking more tokens, withdraw any unlocked ones if possible
        uint256 tokensToWithdraw = indexerStake.tokensWithdrawable();
        if (tokensToWithdraw > 0) {
            _withdraw(indexer);
        }

        // Update the indexer stake locking tokens
        indexerStake.lockTokens(tokensToLock, __thawingPeriod);

        emit StakeLocked(indexer, indexerStake.tokensLocked, indexerStake.tokensLockedUntil);
    }

    /**
     * @notice Withdraw indexer tokens once the thawing period has passed.
     */
    function withdraw() external override notPaused {
        _withdraw(msg.sender);
    }

    /**
     * @notice Set the destination where to send rewards for an indexer.
     * @param _destination Rewards destination address. If set to zero, rewards will be restaked
     */
    function setRewardsDestination(address _destination) external override {
        __rewardsDestination[msg.sender] = _destination;
        emit SetRewardsDestination(msg.sender, _destination);
    }

    /**
     * @notice Allocate available tokens to a subgraph deployment.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocation identifier
     * @param _metadata IPFS hash for additional information about the allocation
     * @param _proof A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`
     */
    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata,
        bytes calldata _proof
    ) external override notPaused {
        _allocate(msg.sender, _subgraphDeploymentID, _tokens, _allocationID, _metadata, _proof);
    }

    /**
     * @notice Allocate available tokens to a subgraph deployment from and indexer's stake.
     * The caller must be the indexer or the indexer's operator.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocation identifier
     * @param _metadata IPFS hash for additional information about the allocation
     * @param _proof A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`
     */
    function allocateFrom(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata,
        bytes calldata _proof
    ) external override notPaused {
        _allocate(_indexer, _subgraphDeploymentID, _tokens, _allocationID, _metadata, _proof);
    }

    /**
     * @notice Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out of rewards set _poi to 0x0
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

        Allocation storage alloc = __allocations[_allocationID];
        bytes32 subgraphDeploymentID = alloc.subgraphDeploymentID;

        uint256 queryFees = _tokens; // Tokens collected from the channel
        uint256 protocolTax = 0; // Tokens burnt as protocol tax
        uint256 curationFees = 0; // Tokens distributed to curators as curation fees
        uint256 queryRebates = 0; // Tokens to distribute to indexer
        uint256 delegationRewards = 0; // Tokens to distribute to delegators

        {
            // -- Pull tokens from the sender --
            IGraphToken graphToken = graphToken();
            TokenUtils.pullTokens(graphToken, msg.sender, queryFees);

            // -- Collect protocol tax --
            protocolTax = _collectTax(graphToken, queryFees, __protocolPercentage);
            queryFees = queryFees.sub(protocolTax);

            // -- Collect curation fees --
            // Only if the subgraph deployment is curated
            curationFees = _collectCurationFees(graphToken, subgraphDeploymentID, queryFees, __curationPercentage);
            queryFees = queryFees.sub(curationFees);

            // -- Process rebate reward --
            // Using accumulated fees and subtracting previously distributed rebates
            // allows for multiple vouchers to be collected while following the rebate formula
            alloc.collectedFees = alloc.collectedFees.add(queryFees);

            // No rebates if indexer has no stake or if lambda is zero
            uint256 newRebates = (alloc.tokens == 0 || __lambdaNumerator == 0)
                ? 0
                : LibExponential.exponentialRebates(
                    alloc.collectedFees,
                    alloc.tokens,
                    __alphaNumerator,
                    __alphaDenominator,
                    __lambdaNumerator,
                    __lambdaDenominator
                );

            //  -- Ensure rebates to distribute are within bounds --
            // Indexers can become under or over rebated if rebate parameters (alpha, lambda)
            // change between successive collect calls for the same allocation

            // Ensure rebates to distribute are not negative (indexer is over-rebated)
            queryRebates = MathUtils.diffOrZero(newRebates, alloc.distributedRebates);

            // Ensure rebates to distribute are not greater than available (indexer is under-rebated)
            queryRebates = MathUtils.min(queryRebates, queryFees);

            // -- Burn rebates remanent --
            TokenUtils.burnTokens(graphToken, queryFees.sub(queryRebates));

            // -- Distribute rebates --
            if (queryRebates > 0) {
                alloc.distributedRebates = alloc.distributedRebates.add(queryRebates);

                // -- Collect delegation rewards into the delegation pool --
                delegationRewards = _collectDelegationQueryRewards(alloc.indexer, queryRebates);
                queryRebates = queryRebates.sub(delegationRewards);

                // -- Transfer or restake rebates --
                _sendRewards(
                    graphToken,
                    queryRebates,
                    alloc.indexer,
                    __rewardsDestination[alloc.indexer] == address(0)
                );
            }
        }

        emit RebateCollected(
            msg.sender,
            alloc.indexer,
            subgraphDeploymentID,
            _allocationID,
            epochManager().currentEpoch(),
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
     * @param _allocationID Address used as signer by the indexer for an allocation
     * @return True if allocationID already used
     */
    function isAllocation(address _allocationID) external view override returns (bool) {
        return _getAllocationState(_allocationID) != AllocationState.Null;
    }

    /**
     * @notice Getter that returns if an indexer has any stake.
     * @param _indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address _indexer) external view override returns (bool) {
        return __stakes[_indexer].tokensStaked > 0;
    }

    /**
     * @notice Return the allocation by ID.
     * @param _allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address _allocationID) external view override returns (Allocation memory) {
        return __allocations[_allocationID];
    }

    /**
     * @notice Return the current state of an allocation
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
        return __subgraphAllocations[_subgraphDeploymentID];
    }

    /**
     * @notice Get the total amount of tokens staked by the indexer.
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address _indexer) external view override returns (uint256) {
        return __stakes[_indexer].tokensStaked;
    }

    /**
     * @notice Deposit tokens on the Indexer stake, on behalf of the Indexer.
     * The amount staked must be over the minimumIndexerStake.
     * @param _indexer Address of the indexer
     * @param _tokens Amount of tokens to stake
     */
    function stakeTo(address _indexer, uint256 _tokens) public override notPartialPaused {
        require(_tokens > 0, "!tokens");

        // Transfer tokens to stake from caller to this contract
        TokenUtils.pullTokens(graphToken(), msg.sender, _tokens);

        // Stake the transferred tokens
        _stake(_indexer, _tokens);
    }

    /**
     * @notice Set the delegation parameters for the caller.
     * @param _indexingRewardCut Percentage of indexing rewards left for the indexer
     * @param _queryFeeCut Percentage of query fees left for the indexer
     */
    function setDelegationParameters(
        uint32 _indexingRewardCut,
        uint32 _queryFeeCut,
        uint32 // _cooldownBlocks, deprecated
    ) public override {
        _setDelegationParameters(msg.sender, _indexingRewardCut, _queryFeeCut);
    }

    /**
     * @notice Get the total amount of tokens available to use in allocations.
     * This considers the indexer stake and delegated tokens according to delegation ratio
     * @param _indexer Address of the indexer
     * @return Amount of tokens available to allocate including delegation
     */
    function getIndexerCapacity(address _indexer) public view override returns (uint256) {
        Stakes.Indexer memory indexerStake = __stakes[_indexer];
        uint256 tokensDelegated = __delegationPools[_indexer].tokens;

        uint256 tokensDelegatedCap = indexerStake.tokensSecureStake().mul(uint256(__delegationRatio));
        uint256 tokensDelegatedCapacity = MathUtils.min(tokensDelegated, tokensDelegatedCap);

        return indexerStake.tokensAvailableWithDelegation(tokensDelegatedCapacity);
    }

    /**
     * @notice Return true if operator is allowed for indexer.
     * @param _operator Address of the operator
     * @param _indexer Address of the indexer
     * @return True if operator is allowed for indexer, false otherwise
     */
    function isOperator(address _operator, address _indexer) public view override returns (bool) {
        return __operatorAuth[_indexer][_operator];
    }

    /**
     * @dev Internal: Set the minimum indexer stake required.
     * @param _minimumIndexerStake Minimum indexer stake
     */
    function _setMinimumIndexerStake(uint256 _minimumIndexerStake) private {
        require(_minimumIndexerStake > 0, "!minimumIndexerStake");
        __minimumIndexerStake = _minimumIndexerStake;
        emit ParameterUpdated("minimumIndexerStake");
    }

    /**
     * @dev Internal: Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function _setThawingPeriod(uint32 _thawingPeriod) private {
        require(_thawingPeriod > 0, "!thawingPeriod");
        __thawingPeriod = _thawingPeriod;
        emit ParameterUpdated("thawingPeriod");
    }

    /**
     * @dev Internal: Set the curation percentage of query fees sent to curators.
     * @param _percentage Percentage of query fees sent to curators
     */
    function _setCurationPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        __curationPercentage = _percentage;
        emit ParameterUpdated("curationPercentage");
    }

    /**
     * @dev Internal: Set a protocol percentage to burn when collecting query fees.
     * @param _percentage Percentage of query fees to burn as protocol fee
     */
    function _setProtocolPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        __protocolPercentage = _percentage;
        emit ParameterUpdated("protocolPercentage");
    }

    /**
     * @dev Internal: Set the max time allowed for indexers stake on allocations.
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function _setMaxAllocationEpochs(uint32 _maxAllocationEpochs) private {
        __maxAllocationEpochs = _maxAllocationEpochs;
        emit ParameterUpdated("maxAllocationEpochs");
    }

    /**
     * @dev Set the rebate parameters.
     * @param _alphaNumerator Numerator of `alpha` in the rebates function
     * @param _alphaDenominator Denominator of `alpha` in the rebates function
     * @param _lambdaNumerator Numerator of `lambda` in the rebates function
     * @param _lambdaDenominator Denominator of `lambda` in the rebates function
     */
    function _setRebateParameters(
        uint32 _alphaNumerator,
        uint32 _alphaDenominator,
        uint32 _lambdaNumerator,
        uint32 _lambdaDenominator
    ) private {
        require(_alphaDenominator > 0, "!alphaDenominator");
        require(_lambdaNumerator > 0, "!lambdaNumerator");
        require(_lambdaDenominator > 0, "!lambdaDenominator");
        __alphaNumerator = _alphaNumerator;
        __alphaDenominator = _alphaDenominator;
        __lambdaNumerator = _lambdaNumerator;
        __lambdaDenominator = _lambdaDenominator;
        emit ParameterUpdated("rebateParameters");
    }

    /**
     * @dev Set the delegation parameters for a particular indexer.
     * @param _indexer Indexer to set delegation parameters
     * @param _indexingRewardCut Percentage of indexing rewards left for delegators
     * @param _queryFeeCut Percentage of query fees left for delegators
     */
    function _setDelegationParameters(address _indexer, uint32 _indexingRewardCut, uint32 _queryFeeCut) internal {
        // Incentives must be within bounds
        require(_queryFeeCut <= MAX_PPM, ">queryFeeCut");
        require(_indexingRewardCut <= MAX_PPM, ">indexingRewardCut");

        DelegationPool storage pool = __delegationPools[_indexer];

        // Update delegation params
        pool.indexingRewardCut = _indexingRewardCut;
        pool.queryFeeCut = _queryFeeCut;
        pool.updatedAtBlock = block.number;

        emit DelegationParametersUpdated(_indexer, _indexingRewardCut, _queryFeeCut, 0);
    }

    /**
     * @dev Stake tokens on the indexer.
     * This function does not check minimum indexer stake requirement to allow
     * to be called by functions that increase the stake when collecting rewards
     * without reverting
     * @param _indexer Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexer, uint256 _tokens) internal {
        // Ensure minimum stake
        require(__stakes[_indexer].tokensSecureStake().add(_tokens) >= __minimumIndexerStake, "!minimumIndexerStake");

        // Deposit tokens into the indexer stake
        __stakes[_indexer].deposit(_tokens);

        // Initialize the delegation pool the first time
        if (__delegationPools[_indexer].updatedAtBlock == 0) {
            _setDelegationParameters(_indexer, MAX_PPM, MAX_PPM);
        }

        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     * @param _indexer Address of indexer to withdraw funds from
     */
    function _withdraw(address _indexer) private {
        // Get tokens available for withdraw and update balance
        uint256 tokensToWithdraw = __stakes[_indexer].withdrawTokens();
        require(tokensToWithdraw > 0, "!tokens");

        // Return tokens to the indexer
        TokenUtils.pushTokens(graphToken(), _indexer, tokensToWithdraw);

        emit StakeWithdrawn(_indexer, tokensToWithdraw);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocationID will work to identify collected funds related to this allocation
     * @param _metadata Metadata related to the allocation
     * @param _proof A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`
     */
    function _allocate(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata,
        bytes calldata _proof
    ) private {
        require(_isAuth(_indexer), "!auth");

        // Check allocation
        require(_allocationID != address(0), "!alloc");
        require(_getAllocationState(_allocationID) == AllocationState.Null, "!null");

        // Caller must prove that they own the private key for the allocationID address
        // The proof is an Ethereum signed message of KECCAK256(indexerAddress,allocationID)
        bytes32 messageHash = keccak256(abi.encodePacked(_indexer, _allocationID));
        bytes32 digest = ECDSA.toEthSignedMessageHash(messageHash);
        require(ECDSA.recover(digest, _proof) == _allocationID, "!proof");

        require(__stakes[_indexer].tokensSecureStake() >= __minimumIndexerStake, "!minimumIndexerStake");
        if (_tokens > 0) {
            // Needs to have free capacity not used for other purposes to allocate
            require(getIndexerCapacity(_indexer) >= _tokens, "!capacity");
        }

        // Creates an allocation
        // Allocation identifiers are not reused
        // Anyone can send collected funds to the allocation using collect()
        Allocation memory alloc = Allocation(
            _indexer,
            _subgraphDeploymentID,
            _tokens, // Tokens allocated
            epochManager().currentEpoch(), // createdAtEpoch
            0, // closedAtEpoch
            0, // Initialize collected fees
            0, // Initialize effective allocation (DEPRECATED)
            (_tokens > 0) ? _updateRewards(_subgraphDeploymentID) : 0, // Initialize accumulated rewards per stake allocated
            0 // Initialize distributed rebates
        );
        __allocations[_allocationID] = alloc;

        // -- Rewards Distribution --

        // Process non-zero-allocation rewards tracking
        if (_tokens > 0) {
            // Mark allocated tokens as used
            __stakes[_indexer].allocate(alloc.tokens);

            // Track total allocations per subgraph
            // Used for rewards calculations
            __subgraphAllocations[alloc.subgraphDeploymentID] = __subgraphAllocations[alloc.subgraphDeploymentID].add(
                alloc.tokens
            );
        }

        emit AllocationCreated(
            _indexer,
            _subgraphDeploymentID,
            alloc.createdAtEpoch,
            alloc.tokens,
            _allocationID,
            _metadata
        );
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
        Allocation memory alloc = __allocations[_allocationID];

        alloc.closedAtEpoch = epochManager().currentEpoch();

        // Allocation duration in epochs
        uint256 epochs = MathUtils.diffOrZero(alloc.closedAtEpoch, alloc.createdAtEpoch);

        // Indexer or operator can close an allocation
        // Anyone is allowed to close ONLY under two concurrent conditions
        // - After maxAllocationEpochs passed
        // - When the allocation is for non-zero amount of tokens
        bool isIndexerOrOperator = _isAuth(alloc.indexer);
        if (epochs <= __maxAllocationEpochs || alloc.tokens == 0) {
            require(isIndexerOrOperator, "!auth");
        }

        // Close the allocation
        __allocations[_allocationID].closedAtEpoch = alloc.closedAtEpoch;

        // -- Rewards Distribution --

        // Process non-zero-allocation rewards tracking
        if (alloc.tokens > 0) {
            // Distribute rewards if proof of indexing was presented by the indexer or operator
            // and the allocation is at least one epoch old (most indexed chains require the EBO
            // posting epoch block numbers to produce a valid POI which happens once per epoch)
            if (isIndexerOrOperator && _poi != 0 && epochs > 0) {
                _distributeRewards(_allocationID, alloc.indexer);
            } else {
                _updateRewards(alloc.subgraphDeploymentID);
            }

            // Free allocated tokens from use
            __stakes[alloc.indexer].unallocate(alloc.tokens);

            // Track total allocations per subgraph
            // Used for rewards calculations
            __subgraphAllocations[alloc.subgraphDeploymentID] = __subgraphAllocations[alloc.subgraphDeploymentID].sub(
                alloc.tokens
            );
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
        DelegationPool storage pool = __delegationPools[_indexer];
        if (pool.tokens > 0 && pool.queryFeeCut < MAX_PPM) {
            uint256 indexerCut = uint256(pool.queryFeeCut).mul(_tokens).div(MAX_PPM);
            delegationRewards = _tokens.sub(indexerCut);
            pool.tokens = pool.tokens.add(delegationRewards);
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
        DelegationPool storage pool = __delegationPools[_indexer];
        if (pool.tokens > 0 && pool.indexingRewardCut < MAX_PPM) {
            uint256 indexerCut = uint256(pool.indexingRewardCut).mul(_tokens).div(MAX_PPM);
            delegationRewards = _tokens.sub(indexerCut);
            pool.tokens = pool.tokens.add(delegationRewards);
        }
        return delegationRewards;
    }

    /**
     * @dev Collect the curation fees for a subgraph deployment from an amount of tokens.
     * This function transfer curation fees to the Curation contract by calling Curation.collect
     * @param _graphToken Token to collect
     * @param _subgraphDeploymentID Subgraph deployment to which the curation fees are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @param _curationPercentage Percentage of tokens to collect as fees
     * @return Amount of curation fees
     */
    function _collectCurationFees(
        IGraphToken _graphToken,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        uint256 _curationPercentage
    ) private returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }

        ICuration curation = curation();
        bool isCurationEnabled = _curationPercentage > 0 && address(curation) != address(0);

        if (isCurationEnabled && curation.isCurated(_subgraphDeploymentID)) {
            // Calculate the tokens after curation fees first, and subtact that,
            // to prevent curation fees from rounding down to zero
            uint256 tokensAfterCurationFees = uint256(MAX_PPM).sub(_curationPercentage).mul(_tokens).div(MAX_PPM);
            uint256 curationFees = _tokens.sub(tokensAfterCurationFees);
            if (curationFees > 0) {
                // Transfer and call collect()
                // This function transfer tokens to a trusted protocol contracts
                // Then we call collect() to do the transfer bookeeping
                rewardsManager().onSubgraphSignalUpdate(_subgraphDeploymentID);
                TokenUtils.pushTokens(_graphToken, address(curation), curationFees);
                curation.collect(_subgraphDeploymentID, curationFees);
            }
            return curationFees;
        }
        return 0;
    }

    /**
     * @dev Collect tax to burn for an amount of tokens.
     * @param _graphToken Token to burn
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @param _percentage Percentage of tokens to burn as tax
     * @return Amount of tax charged
     */
    function _collectTax(IGraphToken _graphToken, uint256 _tokens, uint256 _percentage) private returns (uint256) {
        // Calculate tokens after tax first, and subtract that,
        // to prevent the tax from rounding down to zero
        uint256 tokensAfterTax = uint256(MAX_PPM).sub(_percentage).mul(_tokens).div(MAX_PPM);
        uint256 tax = _tokens.sub(tokensAfterTax);
        TokenUtils.burnTokens(_graphToken, tax); // Burn tax if any
        return tax;
    }

    /**
     * @dev Triggers an update of rewards due to a change in allocations.
     * @param _subgraphDeploymentID Subgraph deployment updated
     * @return Accumulated rewards per allocated token for the subgraph deployment
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) private returns (uint256) {
        IRewardsManager rewardsManager = rewardsManager();
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
        IRewardsManager rewardsManager = rewardsManager();
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
        uint256 indexerRewards = totalRewards.sub(delegationRewards);

        // Send the indexer rewards
        _sendRewards(graphToken(), indexerRewards, _indexer, __rewardsDestination[_indexer] == address(0));
    }

    /**
     * @dev Send rewards to the appropriate destination.
     * @param _graphToken Graph token
     * @param _amount Number of rewards tokens
     * @param _beneficiary Address of the beneficiary of rewards
     * @param _restake Whether to restake or not
     */
    function _sendRewards(IGraphToken _graphToken, uint256 _amount, address _beneficiary, bool _restake) private {
        if (_amount == 0) return;

        if (_restake) {
            // Restake to place fees into the indexer stake
            _stake(_beneficiary, _amount);
        } else {
            // Transfer funds to the beneficiary's designated rewards destination if set
            address destination = __rewardsDestination[_beneficiary];
            TokenUtils.pushTokens(_graphToken, destination == address(0) ? _beneficiary : destination, _amount);
        }
    }

    /**
     * @dev Check if the caller is authorized to operate on behalf of
     * an indexer (i.e. the caller is the indexer or an operator)
     * @param _indexer Indexer address
     * @return True if the caller is authorized to operate on behalf of the indexer
     */
    function _isAuth(address _indexer) private view returns (bool) {
        return msg.sender == _indexer || isOperator(msg.sender, _indexer) == true;
    }

    /**
     * @dev Return the current state of an allocation
     * @param _allocationID Allocation identifier
     * @return AllocationState enum with the state of the allocation
     */
    function _getAllocationState(address _allocationID) private view returns (AllocationState) {
        Allocation storage alloc = __allocations[_allocationID];

        if (alloc.indexer == address(0)) {
            return AllocationState.Null;
        }

        if (alloc.createdAtEpoch != 0 && alloc.closedAtEpoch == 0) {
            return AllocationState.Active;
        }

        return AllocationState.Closed;
    }
}
