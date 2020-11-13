// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "../upgrades/GraphUpgradeable.sol";

import "./IStaking.sol";
import "./StakingStorage.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

/**
 * @title Staking contract
 */
contract Staking is StakingV1Storage, GraphUpgradeable, IStaking {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;
    using Rebates for Rebates.Pool;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    // -- Events --

    /**
     * @dev Emitted when `indexer` update the delegation parameters for its delegation pool.
     */
    event DelegationParametersUpdated(
        address indexed indexer,
        uint32 indexingRewardCut,
        uint32 queryFeeCut,
        uint32 cooldownBlocks
    );

    /**
     * @dev Emitted when `indexer` stake `tokens` amount.
     */
    event StakeDeposited(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` unstaked and locked `tokens` amount `until` block.
     */
    event StakeLocked(address indexed indexer, uint256 tokens, uint256 until);

    /**
     * @dev Emitted when `indexer` withdrew `tokens` staked.
     */
    event StakeWithdrawn(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` was slashed for a total of `tokens` amount.
     * Tracks `reward` amount of tokens given to `beneficiary`.
     */
    event StakeSlashed(
        address indexed indexer,
        uint256 tokens,
        uint256 reward,
        address beneficiary
    );

    /**
     * @dev Emitted when `delegator` delegated `tokens` to the `indexer`, the delegator
     * gets `shares` for the delegation pool proportionally to the tokens staked.
     */
    event StakeDelegated(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
    );

    /**
     * @dev Emitted when `delegator` undelegated `tokens` from `indexer`.
     * Tokens get locked for withdrawal after a period of time.
     */
    event StakeDelegatedLocked(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares,
        uint256 until
    );

    /**
     * @dev Emitted when `delegator` withdrew delegated `tokens` from `indexer`.
     */
    event StakeDelegatedWithdrawn(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens
    );

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphDeploymentID`
     * during `epoch`.
     * `allocationID` indexer derived address used to identify the allocation.
     * `metadata` additional information related to the allocation.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address allocationID,
        bytes32 metadata
    );

    /**
     * @dev Emitted when `indexer` collected `tokens` amount in `epoch` for `allocationID`.
     * These funds are related to `subgraphDeploymentID`.
     * The `from` value is the sender of the collected funds.
     */
    event AllocationCollected(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address allocationID,
        address from,
        uint256 curationFees,
        uint256 rebateFees
    );

    /**
     * @dev Emitted when `indexer` close an allocation in `epoch` for `allocationID`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentID`.
     * The `effectiveAllocation` are the tokens allocated from creation to closing.
     * This event also emits the POI (proof of indexing) submitted by the indexer.
     */
    event AllocationClosed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address allocationID,
        uint256 effectiveAllocation,
        address sender,
        bytes32 poi
    );

    /**
     * @dev Emitted when `indexer` claimed a rebate on `subgraphDeploymentID` during `epoch`
     * related to the `forEpoch` rebate pool.
     * The rebate is for `tokens` amount and `unclaimedAllocationsCount` are left for claim
     * in the rebate pool. `delegationFees` collected and sent to delegation pool.
     */
    event RebateClaimed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        address allocationID,
        uint256 epoch,
        uint256 forEpoch,
        uint256 tokens,
        uint256 unclaimedAllocationsCount,
        uint256 delegationFees
    );

    /**
     * @dev Emitted when `caller` set `slasher` address as `allowed` to slash stakes.
     */
    event SlasherUpdate(address indexed caller, address indexed slasher, bool allowed);

    /**
     * @dev Emitted when `caller` set `assetHolder` address as `allowed` to send funds
     * to staking contract.
     */
    event AssetHolderUpdate(address indexed caller, address indexed assetHolder, bool allowed);

    /**
     * @dev Emitted when `indexer` set `operator` access.
     */
    event SetOperator(address indexed indexer, address operator, bool allowed);

    /**
     * @dev Check if the caller is the slasher.
     */
    modifier onlySlasher {
        require(slashers[msg.sender] == true, "!slasher");
        _;
    }

    /**
     * @dev Check if the caller is authorized (indexer or operator)
     */
    function _isAuth(address _indexer) private view returns (bool) {
        return msg.sender == _indexer || isOperator(msg.sender, _indexer) == true;
    }

    /**
     * @dev Check if the caller is authorized (indexer, operator or delegator)
     */
    function _isAuthOrDelegator(address _indexer) private view returns (bool) {
        return _isAuth(_indexer) || delegationPools[_indexer].delegators[msg.sender].shares > 0;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(
        address _controller,
        uint256 _minimumIndexerStake,
        uint32 _thawingPeriod,
        uint32 _protocolPercentage,
        uint32 _curationPercentage,
        uint32 _channelDisputeEpochs,
        uint32 _maxAllocationEpochs,
        uint32 _delegationUnbondingPeriod,
        uint32 _delegationRatio,
        uint32 _rebateAlphaNumerator,
        uint32 _rebateAlphaDenominator
    ) external onlyImpl {
        Managed._initialize(_controller);

        // Settings
        _setMinimumIndexerStake(_minimumIndexerStake);
        _setThawingPeriod(_thawingPeriod);

        _setProtocolPercentage(_protocolPercentage);
        _setCurationPercentage(_curationPercentage);

        _setChannelDisputeEpochs(_channelDisputeEpochs);
        _setMaxAllocationEpochs(_maxAllocationEpochs);

        _setDelegationUnbondingPeriod(_delegationUnbondingPeriod);
        _setDelegationRatio(_delegationRatio);
        _setDelegationParametersCooldown(0);
        _setDelegationTaxPercentage(0);

        _setRebateRatio(_rebateAlphaNumerator, _rebateAlphaDenominator);
    }

    /**
     * @dev Set the minimum indexer stake required to.
     * @param _minimumIndexerStake Minimum indexer stake
     */
    function setMinimumIndexerStake(uint256 _minimumIndexerStake) external override onlyGovernor {
        _setMinimumIndexerStake(_minimumIndexerStake);
    }

    /**
     * @dev Internal: Set the minimum indexer stake required.
     * @param _minimumIndexerStake Minimum indexer stake
     */
    function _setMinimumIndexerStake(uint256 _minimumIndexerStake) private {
        minimumIndexerStake = _minimumIndexerStake;
        emit ParameterUpdated("minimumIndexerStake");
    }

    /**
     * @dev Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function setThawingPeriod(uint32 _thawingPeriod) external override onlyGovernor {
        _setThawingPeriod(_thawingPeriod);
    }

    /**
     * @dev Internal: Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function _setThawingPeriod(uint32 _thawingPeriod) private {
        thawingPeriod = _thawingPeriod;
        emit ParameterUpdated("thawingPeriod");
    }

    /**
     * @dev Set the curation percentage of query fees sent to curators.
     * @param _percentage Percentage of query fees sent to curators
     */
    function setCurationPercentage(uint32 _percentage) external override onlyGovernor {
        _setCurationPercentage(_percentage);
    }

    /**
     * @dev Internal: Set the curation percentage of query fees sent to curators.
     * @param _percentage Percentage of query fees sent to curators
     */
    function _setCurationPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        curationPercentage = _percentage;
        emit ParameterUpdated("curationPercentage");
    }

    /**
     * @dev Set a protocol percentage to burn when collecting query fees.
     * @param _percentage Percentage of query fees to burn as protocol fee
     */
    function setProtocolPercentage(uint32 _percentage) external override onlyGovernor {
        _setProtocolPercentage(_percentage);
    }

    /**
     * @dev Internal: Set a protocol percentage to burn when collecting query fees.
     * @param _percentage Percentage of query fees to burn as protocol fee
     */
    function _setProtocolPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        protocolPercentage = _percentage;
        emit ParameterUpdated("protocolPercentage");
    }

    /**
     * @dev Set the period in epochs that need to pass before fees in rebate pool can be claimed.
     * @param _channelDisputeEpochs Period in epochs
     */
    function setChannelDisputeEpochs(uint32 _channelDisputeEpochs) external override onlyGovernor {
        _setChannelDisputeEpochs(_channelDisputeEpochs);
    }

    /**
     * @dev Internal: Set the period in epochs that need to pass before fees in rebate pool can be claimed.
     * @param _channelDisputeEpochs Period in epochs
     */
    function _setChannelDisputeEpochs(uint32 _channelDisputeEpochs) private {
        channelDisputeEpochs = _channelDisputeEpochs;
        emit ParameterUpdated("channelDisputeEpochs");
    }

    /**
     * @dev Set the max time allowed for indexers stake on allocations.
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function setMaxAllocationEpochs(uint32 _maxAllocationEpochs) external override onlyGovernor {
        _setMaxAllocationEpochs(_maxAllocationEpochs);
    }

    /**
     * @dev Internal: Set the max time allowed for indexers stake on allocations.
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function _setMaxAllocationEpochs(uint32 _maxAllocationEpochs) private {
        maxAllocationEpochs = _maxAllocationEpochs;
        emit ParameterUpdated("maxAllocationEpochs");
    }

    /**
     * @dev Set the rebate ratio (fees to allocated stake).
     * @param _alphaNumerator Numerator of `alpha` in the cobb-douglas function
     * @param _alphaDenominator Denominator of `alpha` in the cobb-douglas function
     */
    function setRebateRatio(uint32 _alphaNumerator, uint32 _alphaDenominator)
        external
        override
        onlyGovernor
    {
        _setRebateRatio(_alphaNumerator, _alphaDenominator);
    }

    /**
     * @dev Set the rebate ratio (fees to allocated stake).
     * @param _alphaNumerator Numerator of `alpha` in the cobb-douglas function
     * @param _alphaDenominator Denominator of `alpha` in the cobb-douglas function
     */
    function _setRebateRatio(uint32 _alphaNumerator, uint32 _alphaDenominator) private {
        require(_alphaNumerator > 0 && _alphaDenominator > 0, "!alpha");
        alphaNumerator = _alphaNumerator;
        alphaDenominator = _alphaDenominator;
        emit ParameterUpdated("rebateRatio");
    }

    /**
     * @dev Set the delegation ratio.
     * If set to 10 it means the indexer can use up to 10x the indexer staked amount
     * from their delegated tokens
     * @param _delegationRatio Delegation capacity multiplier
     */
    function setDelegationRatio(uint32 _delegationRatio) external override onlyGovernor {
        _setDelegationRatio(_delegationRatio);
    }

    /**
     * @dev Internal: Set the delegation ratio.
     * If set to 10 it means the indexer can use up to 10x the indexer staked amount
     * from their delegated tokens
     * @param _delegationRatio Delegation capacity multiplier
     */
    function _setDelegationRatio(uint32 _delegationRatio) private {
        delegationRatio = _delegationRatio;
        emit ParameterUpdated("delegationRatio");
    }

    /**
     * @dev Set the delegation parameters.
     * @param _indexingRewardCut Percentage of indexing rewards left for delegators
     * @param _queryFeeCut Percentage of query fees left for delegators
     * @param _cooldownBlocks Period that need to pass to update delegation parameters
     */
    function setDelegationParameters(
        uint32 _indexingRewardCut,
        uint32 _queryFeeCut,
        uint32 _cooldownBlocks
    ) public override {
        address indexer = msg.sender;

        // Incentives must be within bounds
        require(_queryFeeCut <= MAX_PPM, ">queryFeeCut");
        require(_indexingRewardCut <= MAX_PPM, ">indexingRewardCut");

        // Cooldown period set by indexer cannot be below protocol global setting
        require(_cooldownBlocks >= delegationParametersCooldown, "<cooldown");

        // Verify the cooldown period passed
        DelegationPool storage pool = delegationPools[indexer];
        require(
            pool.updatedAtBlock == 0 ||
                pool.updatedAtBlock.add(uint256(pool.cooldownBlocks)) <= block.number,
            "!cooldown"
        );

        // Update delegation params
        pool.indexingRewardCut = _indexingRewardCut;
        pool.queryFeeCut = _queryFeeCut;
        pool.cooldownBlocks = _cooldownBlocks;
        pool.updatedAtBlock = block.number;

        emit DelegationParametersUpdated(
            indexer,
            _indexingRewardCut,
            _queryFeeCut,
            _cooldownBlocks
        );
    }

    /**
     * @dev Set the time in blocks an indexer needs to wait to change delegation parameters.
     * @param _blocks Number of blocks to set the delegation parameters cooldown period
     */
    function setDelegationParametersCooldown(uint32 _blocks) external override onlyGovernor {
        _setDelegationParametersCooldown(_blocks);
    }

    /**
     * @dev Internal: Set the time in blocks an indexer needs to wait to change delegation parameters.
     * @param _blocks Number of blocks to set the delegation parameters cooldown period
     */
    function _setDelegationParametersCooldown(uint32 _blocks) private {
        delegationParametersCooldown = _blocks;
        emit ParameterUpdated("delegationParametersCooldown");
    }

    /**
     * @dev Set the period for undelegation of stake from indexer.
     * @param _delegationUnbondingPeriod Period in epochs to wait for token withdrawals after undelegating
     */
    function setDelegationUnbondingPeriod(uint32 _delegationUnbondingPeriod)
        external
        override
        onlyGovernor
    {
        _setDelegationUnbondingPeriod(_delegationUnbondingPeriod);
    }

    /**
     * @dev Internal: Set the period for undelegation of stake from indexer.
     * @param _delegationUnbondingPeriod Period in epochs to wait for token withdrawals after undelegating
     */
    function _setDelegationUnbondingPeriod(uint32 _delegationUnbondingPeriod) private {
        delegationUnbondingPeriod = _delegationUnbondingPeriod;
        emit ParameterUpdated("delegationUnbondingPeriod");
    }

    /**
     * @dev Set a delegation tax percentage to burn when delegated funds are deposited.
     * @param _percentage Percentage of delegated tokens to burn as delegation tax
     */
    function setDelegationTaxPercentage(uint32 _percentage) external override onlyGovernor {
        _setDelegationTaxPercentage(_percentage);
    }

    /**
     * @dev Internal: Set a delegation tax percentage to burn when delegated funds are deposited.
     * @param _percentage Percentage of delegated tokens to burn as delegation tax
     */
    function _setDelegationTaxPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, ">percentage");
        delegationTaxPercentage = _percentage;
        emit ParameterUpdated("delegationTaxPercentage");
    }

    /**
     * @dev Set an address as allowed slasher.
     * @param _slasher Address of the party allowed to slash indexers
     * @param _allowed True if slasher is allowed
     */
    function setSlasher(address _slasher, bool _allowed) external override onlyGovernor {
        require(_slasher != address(0), "!slasher");
        slashers[_slasher] = _allowed;
        emit SlasherUpdate(msg.sender, _slasher, _allowed);
    }

    /**
     * @dev Set an address as allowed asset holder.
     * @param _assetHolder Address of allowed source for state channel funds
     * @param _allowed True if asset holder is allowed
     */
    function setAssetHolder(address _assetHolder, bool _allowed) external override onlyGovernor {
        require(_assetHolder != address(0), "!assetHolder");
        assetHolders[_assetHolder] = _allowed;
        emit AssetHolderUpdate(msg.sender, _assetHolder, _allowed);
    }

    /**
     * @dev Return if allocationID is used.
     * @param _allocationID Address used as signer by the indexer for an allocation
     * @return True if allocationID already used
     */
    function isChannel(address _allocationID) external override view returns (bool) {
        return _getAllocationState(_allocationID) != AllocationState.Null;
    }

    /**
     * @dev Getter that returns if an indexer has any stake.
     * @param _indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address _indexer) external override view returns (bool) {
        return stakes[_indexer].hasTokens();
    }

    /**
     * @dev Return the allocation by ID.
     * @param _allocationID Address used as allocation identifier
     * @return Allocation data
     */
    function getAllocation(address _allocationID)
        external
        override
        view
        returns (Allocation memory)
    {
        return allocations[_allocationID];
    }

    /**
     * @dev Return the current state of an allocation.
     * @param _allocationID Address used as the allocation identifier
     * @return AllocationState
     */
    function getAllocationState(address _allocationID)
        external
        override
        view
        returns (AllocationState)
    {
        return _getAllocationState(_allocationID);
    }

    /**
     * @dev Return the total amount of tokens allocated to subgraph.
     * @param _subgraphDeploymentID Address used as the allocation identifier
     * @return Total tokens allocated to subgraph
     */
    function getSubgraphAllocatedTokens(bytes32 _subgraphDeploymentID)
        external
        override
        view
        returns (uint256)
    {
        return subgraphAllocations[_subgraphDeploymentID];
    }

    /**
     * @dev Return the delegation from a delegator to an indexer.
     * @param _indexer Address of the indexer where funds have been delegated
     * @param _delegator Address of the delegator
     * @return Delegation data
     */
    function getDelegation(address _indexer, address _delegator)
        external
        override
        view
        returns (Delegation memory)
    {
        return delegationPools[_indexer].delegators[_delegator];
    }

    /**
     * @dev Get the total amount of tokens staked by the indexer.
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address _indexer) external override view returns (uint256) {
        return stakes[_indexer].tokensStaked;
    }

    /**
     * @dev Get the total amount of tokens available to use in allocations.
     * This considers the indexer stake and delegated tokens according to delegation ratio
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerCapacity(address _indexer) public override view returns (uint256) {
        Stakes.Indexer memory indexerStake = stakes[_indexer];
        DelegationPool storage pool = delegationPools[_indexer];

        uint256 tokensDelegatedMax = indexerStake.tokensStaked.mul(uint256(delegationRatio));
        uint256 tokensDelegated = (pool.tokens < tokensDelegatedMax)
            ? pool.tokens
            : tokensDelegatedMax;

        return indexerStake.tokensAvailableWithDelegation(tokensDelegated);
    }

    /**
     * @dev Returns amount of delegated tokens ready to be withdrawn after unbonding period.
     * @param _delegation Delegation of tokens from delegator to indexer
     * @return Amount of tokens to withdraw
     */
    function getWithdraweableDelegatedTokens(Delegation memory _delegation)
        public
        view
        returns (uint256)
    {
        // There must be locked tokens and period passed
        uint256 currentEpoch = epochManager().currentEpoch();
        if (_delegation.tokensLockedUntil > 0 && currentEpoch >= _delegation.tokensLockedUntil) {
            return _delegation.tokensLocked;
        }
        return 0;
    }

    /**
     * @dev Authorize an address to be an operator.
     * @param _operator Address to authorize
     * @param _allowed Whether authorized or not
     */
    function setOperator(address _operator, bool _allowed) external override {
        require(_operator != msg.sender, "operator == sender");
        operatorAuth[msg.sender][_operator] = _allowed;
        emit SetOperator(msg.sender, _operator, _allowed);
    }

    /**
     * @dev Return true if operator is allowed for indexer.
     * @param _operator Address of the operator
     * @param _indexer Address of the indexer
     */
    function isOperator(address _operator, address _indexer) public override view returns (bool) {
        return operatorAuth[_indexer][_operator];
    }

    /**
     * @dev Deposit tokens on the indexer stake.
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external override {
        stakeTo(msg.sender, _tokens);
    }

    /**
     * @dev Deposit tokens on the indexer stake.
     * @param _indexer Adress of the indexer
     * @param _tokens Amount of tokens to stake
     */
    function stakeTo(address _indexer, uint256 _tokens) public override notPartialPaused {
        require(_tokens > 0, "!tokens");

        // Ensure minimum stake
        require(
            stakes[_indexer].tokensSecureStake().add(_tokens) >= minimumIndexerStake,
            "!minimumIndexerStake"
        );

        // Transfer tokens to stake from caller to this contract
        require(graphToken().transferFrom(msg.sender, address(this), _tokens), "!transfer");

        // Stake the transferred tokens
        _stake(_indexer, _tokens);
    }

    /**
     * @dev Unstake tokens from the indexer stake, lock them until thawing period expires.
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external override notPartialPaused {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        require(_tokens > 0, "!tokens");
        require(indexerStake.hasTokens(), "!stake");
        require(indexerStake.tokensAvailable() >= _tokens, "!stake-avail");

        // Ensure minimum stake
        uint256 newStake = indexerStake.tokensSecureStake().sub(_tokens);
        require(newStake == 0 || newStake >= minimumIndexerStake, "!minimumIndexerStake");

        // Before locking more tokens, withdraw any unlocked ones
        uint256 tokensToWithdraw = indexerStake.tokensWithdrawable();
        if (tokensToWithdraw > 0) {
            _withdraw(indexer);
        }

        indexerStake.lockTokens(_tokens, thawingPeriod);

        emit StakeLocked(indexer, indexerStake.tokensLocked, indexerStake.tokensLockedUntil);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     */
    function withdraw() external override notPaused {
        _withdraw(msg.sender);
    }

    /**
     * @dev Slash the indexer stake. Delegated tokens are not subject to slashing.
     * Can only be called by the slasher role.
     * @param _indexer Address of indexer to slash
     * @param _tokens Amount of tokens to slash from the indexer stake
     * @param _reward Amount of reward tokens to send to a beneficiary
     * @param _beneficiary Address of a beneficiary to receive a reward for the slashing
     */
    function slash(
        address _indexer,
        uint256 _tokens,
        uint256 _reward,
        address _beneficiary
    ) external override onlySlasher notPartialPaused {
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        // Only able to slash a non-zero number of tokens
        require(_tokens > 0, "!tokens");

        // Rewards comes from tokens slashed balance
        require(_tokens >= _reward, "rewards>slash");

        // Cannot slash stake of an indexer without any or enough stake
        require(indexerStake.hasTokens(), "!stake");
        require(_tokens <= indexerStake.tokensStaked, "slash>stake");

        // Validate beneficiary of slashed tokens
        require(_beneficiary != address(0), "!beneficiary");

        // Slashing more tokens than freely available (over allocation condition)
        // Unlock locked tokens to avoid the indexer to withdraw them
        if (_tokens > indexerStake.tokensAvailable() && indexerStake.tokensLocked > 0) {
            uint256 tokensOverAllocated = _tokens.sub(indexerStake.tokensAvailable());
            uint256 tokensToUnlock = (tokensOverAllocated > indexerStake.tokensLocked)
                ? indexerStake.tokensLocked
                : tokensOverAllocated;
            indexerStake.unlockTokens(tokensToUnlock);
        }

        // Remove tokens to slash from the stake
        indexerStake.release(_tokens);

        // -- Interactions --

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        _burnTokens(_tokens.sub(_reward));

        // Give the beneficiary a reward for slashing
        if (_reward > 0) {
            require(graphToken().transfer(_beneficiary, _reward), "!transfer");
        }

        emit StakeSlashed(_indexer, _tokens, _reward, _beneficiary);
    }

    /**
     * @dev Delegate tokens to an indexer.
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued of the delegation pool
     */
    function delegate(address _indexer, uint256 _tokens)
        external
        override
        notPartialPaused
        returns (uint256)
    {
        address delegator = msg.sender;

        // Transfer tokens to delegate to this contract
        require(graphToken().transferFrom(delegator, address(this), _tokens), "!transfer");

        // Update state
        return _delegate(delegator, _indexer, _tokens);
    }

    /**
     * @dev Undelegate tokens from an indexer.
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function undelegate(address _indexer, uint256 _shares)
        external
        override
        notPartialPaused
        returns (uint256)
    {
        return _undelegate(msg.sender, _indexer, _shares);
    }

    /**
     * @dev Withdraw delegated tokens once the unbonding period has passed.
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _delegateToIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function withdrawDelegated(address _indexer, address _delegateToIndexer)
        external
        override
        notPaused
        returns (uint256)
    {
        return _withdrawDelegated(msg.sender, _indexer, _delegateToIndexer);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocation identifier
     * @param _metadata IPFS hash for additional information about the allocation
     */
    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata
    ) external override notPaused {
        _allocate(msg.sender, _subgraphDeploymentID, _tokens, _allocationID, _metadata);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocation identifier
     * @param _metadata IPFS hash for additional information about the allocation
     */
    function allocateFrom(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata
    ) external override notPaused {
        _allocate(_indexer, _subgraphDeploymentID, _tokens, _allocationID, _metadata);
    }

    /**
     * @dev Close an allocation and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out for rewards set _poi to 0x0
     * @param _allocationID The allocation identifier
     * @param _poi Proof of indexing submitted for the allocated period
     */
    function closeAllocation(address _allocationID, bytes32 _poi) external override notPaused {
        _closeAllocation(_allocationID, _poi);
    }

    /**
     * @dev Close multiple allocations and free the staked tokens.
     * To be eligible for rewards a proof of indexing must be presented.
     * Presenting a bad proof is subject to slashable condition.
     * To opt out for rewards set _poi to 0x0
     * @param _requests An array of CloseAllocationRequest
     */
    function closeAllocationMany(CloseAllocationRequest[] calldata _requests)
        external
        override
        notPaused
    {
        for (uint256 i = 0; i < _requests.length; i++) {
            _closeAllocation(_requests[i].allocationID, _requests[i].poi);
        }
    }

    /**
     * @dev Close and allocate. This will perform a close and then create a new Allocation
     * atomically on the same transaction.
     * @param _closingAllocationID The identifier of the allocation to be closed
     * @param _poi Proof of indexing submitted for the allocated period
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocation identifier
     * @param _metadata IPFS hash for additional information about the allocation
     */
    function closeAndAllocate(
        address _closingAllocationID,
        bytes32 _poi,
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata
    ) external override notPaused {
        _closeAllocation(_closingAllocationID, _poi);
        _allocate(_indexer, _subgraphDeploymentID, _tokens, _allocationID, _metadata);
    }

    /**
     * @dev Collect query fees for an allocation from state channels.
     * Funds received are only accepted from a valid source.
     * @param _tokens Amount of tokens to collect
     */
    function collect(uint256 _tokens, address _allocationID) external override {
        // Allocation identifier validation
        require(_allocationID != address(0), "!alloc");

        // The contract caller must be an authorized asset holder
        require(assetHolders[msg.sender] == true, "!assetHolder");

        // Transfer tokens to collect from the authorized sender
        require(graphToken().transferFrom(msg.sender, address(this), _tokens), "!transfer");

        _collect(_allocationID, msg.sender, _tokens);
    }

    /**
     * @dev Claim tokens from the rebate pool.
     * @param _allocationID Allocation from where we are claiming tokens
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claim(address _allocationID, bool _restake) external override notPaused {
        _claim(_allocationID, _restake);
    }

    /**
     * @dev Claim tokens from the rebate pool for many allocations.
     * @param _allocationID Array of allocations from where we are claiming tokens
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claimMany(address[] calldata _allocationID, bool _restake)
        external
        override
        notPaused
    {
        for (uint256 i = 0; i < _allocationID.length; i++) {
            _claim(_allocationID[i], _restake);
        }
    }

    /**
     * @dev Stake tokens on the indexer.
     * This function does not check minimum indexer stake requirement to allow
     * to be called by functions that increase the stake when collecting rewards
     * without reverting
     * @param _indexer Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexer, uint256 _tokens) private {
        // Deposit tokens into the indexer stake
        Stakes.Indexer storage indexerStake = stakes[_indexer];
        indexerStake.deposit(_tokens);

        // Initialize the delegation pool the first time
        if (delegationPools[_indexer].updatedAtBlock == 0) {
            setDelegationParameters(MAX_PPM, MAX_PPM, delegationParametersCooldown);
        }

        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     * @param _indexer Address of indexer to withdraw funds from
     */
    function _withdraw(address _indexer) private {
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        // Get tokens available for withdraw and update balance
        uint256 tokensToWithdraw = indexerStake.withdrawTokens();
        require(tokensToWithdraw > 0, "!tokens");

        // Return tokens to the indexer
        require(graphToken().transfer(_indexer, tokensToWithdraw), "!transfer");

        emit StakeWithdrawn(_indexer, tokensToWithdraw);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _allocationID The allocationID will work to identify collected funds related to this allocation
     * @param _metadata Metadata related to the allocation
     */
    function _allocate(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata
    ) private {
        require(_isAuth(_indexer), "!auth");

        Stakes.Indexer storage indexerStake = stakes[_indexer];

        // Only allocations with a non-zero token amount are allowed
        require(_tokens > 0, "!tokens");

        // Check allocation ID
        require(_allocationID != address(0), "!alloc");

        // Needs to have free capacity not used for other purposes to allocate
        require(getIndexerCapacity(_indexer) >= _tokens, "!capacity");

        // Cannot reuse an allocationID that has already been used in an allocation
        require(_getAllocationState(_allocationID) == AllocationState.Null, "!null");

        // Creates an allocation
        // Allocation identifiers are not reused
        // The assetHolder address can send collected funds to the allocation
        Allocation memory alloc = Allocation(
            _indexer,
            _subgraphDeploymentID,
            _tokens, // Tokens allocated
            epochManager().currentEpoch(), // createdAtEpoch
            0, // closedAtEpoch
            0, // Initialize collected fees
            0, // Initialize effective allocation
            _updateRewards(_subgraphDeploymentID) // Initialize accumulated rewards per stake allocated
        );
        allocations[_allocationID] = alloc;

        // Mark allocated tokens as used
        indexerStake.allocate(alloc.tokens);

        // Track total allocations per subgraph
        // Used for rewards calculations
        subgraphAllocations[alloc.subgraphDeploymentID] = subgraphAllocations[alloc
            .subgraphDeploymentID]
            .add(alloc.tokens);

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
        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // Allocation must exist and be active
        require(allocState == AllocationState.Active, "!active");

        // Get indexer stakes
        Stakes.Indexer storage indexerStake = stakes[alloc.indexer];

        // Validate that an allocation cannot be closed before one epoch
        uint256 currentEpoch = epochManager().currentEpoch();
        uint256 epochs = alloc.createdAtEpoch < currentEpoch
            ? currentEpoch.sub(alloc.createdAtEpoch)
            : 0;
        require(epochs > 0, "<epochs");

        // Validate ownership
        if (epochs > maxAllocationEpochs) {
            // Verify that the allocation owner or delegator is closing
            require(_isAuthOrDelegator(alloc.indexer), "!auth-or-del");
        } else {
            // Verify that the allocation owner is closing
            require(_isAuth(alloc.indexer), "!auth");
        }

        // Close the allocation and start counting a period to settle remaining payments from
        // state channels.
        alloc.closedAtEpoch = currentEpoch;
        alloc.effectiveAllocation = _getEffectiveAllocation(alloc.tokens, epochs);

        // Account collected fees and effective allocation in rebate pool for the epoch
        Rebates.Pool storage rebatePool = rebates[currentEpoch];
        if (!rebatePool.exists()) {
            rebatePool.init(alphaNumerator, alphaDenominator);
        }
        rebatePool.addToPool(alloc.collectedFees, alloc.effectiveAllocation);

        // Distribute rewards if proof of indexing was presented by the indexer or operator
        if (_isAuth(msg.sender) && _poi != 0) {
            _distributeRewards(_allocationID, alloc.indexer);
        }

        // Free allocated tokens from use
        indexerStake.unallocate(alloc.tokens);

        // Track total allocations per subgraph
        // Used for rewards calculations
        subgraphAllocations[alloc.subgraphDeploymentID] = subgraphAllocations[alloc
            .subgraphDeploymentID]
            .sub(alloc.tokens);

        emit AllocationClosed(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            alloc.closedAtEpoch,
            alloc.tokens,
            _allocationID,
            alloc.effectiveAllocation,
            msg.sender,
            _poi
        );
    }

    /**
     * @dev Collect query fees for an allocation from the state channel.
     * @param _allocationID Allocation that is receiving query fees
     * @param _from Source of collected funds for the allocation
     * @param _tokens Amount of tokens to collect
     */
    function _collect(
        address _allocationID,
        address _from,
        uint256 _tokens
    ) private {
        uint256 queryFees = _tokens;

        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // The allocation must exist
        require(allocState != AllocationState.Null, "!collect");

        // Process protocol fees
        uint256 protocolFees = 0;
        if (allocState == AllocationState.Active || allocState == AllocationState.Closed) {
            // Calculate protocol fees to be burned under normal conditions
            protocolFees = _collectProtocolFees(queryFees);
            queryFees = queryFees.sub(protocolFees);
        } else {
            // Protocol tax is 100% for collected query fees over channelDisputePeriod
            protocolFees = queryFees;
            queryFees = 0;
        }

        // Calculate curation fees (only if the subgraph deployment is curated)
        uint256 curationFees = _collectCurationFees(alloc.subgraphDeploymentID, queryFees);
        queryFees = queryFees.sub(curationFees);

        // Collect funds on the allocation
        alloc.collectedFees = alloc.collectedFees.add(queryFees);

        // When allocation is closed redirect funds to the rebate pool
        // This way we can keep collecting tokens even after the allocation is closed and
        // before it gets to the finalized state.
        if (allocState == AllocationState.Closed) {
            Rebates.Pool storage rebatePool = rebates[alloc.closedAtEpoch];
            rebatePool.fees = rebatePool.fees.add(queryFees);
        }

        // -- Interactions --

        // Burn protocol fees if any
        _burnTokens(protocolFees);

        // Send curation fees to the curator reserve pool
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            ICuration curation = curation();
            require(graphToken().approve(address(curation), curationFees), "!approve");
            curation.collect(alloc.subgraphDeploymentID, curationFees);
        }

        emit AllocationCollected(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            epochManager().currentEpoch(),
            _tokens,
            _allocationID,
            _from,
            curationFees,
            queryFees
        );
    }

    /**
     * @dev Claim tokens from the rebate pool.
     * @param _allocationID Allocation from where we are claiming tokens
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function _claim(address _allocationID, bool _restake) private {
        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // Only the indexer or operator can decide if to restake
        bool restake = _isAuth(alloc.indexer) ? _restake : false;

        // Funds can only be claimed after a period of time passed since allocation was closed
        require(allocState == AllocationState.Finalized, "!finalized");

        // Process rebate reward
        Rebates.Pool storage rebatePool = rebates[alloc.closedAtEpoch];
        uint256 tokensToClaim = rebatePool.redeem(alloc.collectedFees, alloc.effectiveAllocation);

        // Calculate delegation rewards and add them to the delegation pool
        uint256 delegationRewards = _collectDelegationQueryRewards(alloc.indexer, tokensToClaim);
        tokensToClaim = tokensToClaim.sub(delegationRewards);

        // Purge allocation data except for:
        // - indexer: used in disputes and to avoid reusing an allocationID
        // - subgraphDeploymentID: used in disputes
        uint256 closedAtEpoch = alloc.closedAtEpoch;
        alloc.tokens = 0; // This avoid collect(), close() and claim() to be called
        alloc.createdAtEpoch = 0;
        alloc.closedAtEpoch = 0;
        alloc.collectedFees = 0;
        alloc.effectiveAllocation = 0;

        // -- Interactions --

        // When all allocations processed then burn unclaimed fees and prune rebate pool
        if (rebatePool.unclaimedAllocationsCount == 0) {
            _burnTokens(rebatePool.unclaimedFees());
            delete rebates[closedAtEpoch];
        }

        // When there are tokens to claim from the rebate pool, transfer or restake
        if (tokensToClaim > 0) {
            // Assign claimed tokens
            if (restake) {
                // Restake to place fees into the indexer stake
                _stake(alloc.indexer, tokensToClaim);
            } else {
                // Transfer funds back to the indexer
                require(graphToken().transfer(alloc.indexer, tokensToClaim), "!transfer");
            }
        }

        emit RebateClaimed(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            _allocationID,
            epochManager().currentEpoch(),
            closedAtEpoch,
            tokensToClaim,
            rebatePool.unclaimedAllocationsCount,
            delegationRewards
        );
    }

    /**
     * @dev Delegate tokens to an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     * @return Amount of shares issued of the delegation pool
     */
    function _delegate(
        address _delegator,
        address _indexer,
        uint256 _tokens
    ) private returns (uint256) {
        // Only delegate a non-zero amount of tokens
        require(_tokens > 0, "!tokens");
        // Only delegate to non-empty address
        require(_indexer != address(0), "!indexer");
        // Only delegate to staked indexer
        require(stakes[_indexer].hasTokens(), "!stake");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Collect delegation tax
        uint256 delegationTax = _collectDelegationTax(_tokens);
        uint256 delegatedTokens = _tokens.sub(delegationTax);

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0)
            ? delegatedTokens
            : delegatedTokens.mul(pool.shares).div(pool.tokens);

        // Update the delegation pool
        pool.tokens = pool.tokens.add(delegatedTokens);
        pool.shares = pool.shares.add(shares);

        // Update the delegation
        delegation.shares = delegation.shares.add(shares);

        // -- Interactions --

        // Burn the delegation tax if any
        _burnTokens(delegationTax);

        emit StakeDelegated(_indexer, _delegator, delegatedTokens, shares);

        return shares;
    }

    /**
     * @dev Undelegate tokens from an indexer.
     * @param _delegator Address of the delegator
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     * @return Amount of tokens returned for the shares of the delegation pool
     */
    function _undelegate(
        address _delegator,
        address _indexer,
        uint256 _shares
    ) private returns (uint256) {
        // Can only undelegate a non-zero amount of shares
        require(_shares > 0, "!shares");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Delegator need to have enough shares in the pool to undelegate
        require(delegation.shares >= _shares, "!shares-avail");

        // Withdraw tokens if available
        if (getWithdraweableDelegatedTokens(delegation) > 0) {
            _withdrawDelegated(_delegator, _indexer, address(0));
        }

        // Calculate tokens to get in exchange for the shares
        uint256 tokens = _shares.mul(pool.tokens).div(pool.shares);

        // Update the delegation pool
        pool.tokens = pool.tokens.sub(tokens);
        pool.shares = pool.shares.sub(_shares);

        // Update the delegation
        delegation.shares = delegation.shares.sub(_shares);
        delegation.tokensLocked = delegation.tokensLocked.add(tokens);
        delegation.tokensLockedUntil = epochManager().currentEpoch().add(delegationUnbondingPeriod);

        emit StakeDelegatedLocked(
            _indexer,
            _delegator,
            tokens,
            _shares,
            delegation.tokensLockedUntil
        );

        return tokens;
    }

    /**
     * @dev Withdraw delegated tokens once the unbonding period has passed.
     * @param _delegator Delegator that is withdrawing tokens
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _delegateToIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function _withdrawDelegated(
        address _delegator,
        address _indexer,
        address _delegateToIndexer
    ) private returns (uint256) {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Validation
        uint256 tokensToWithdraw = getWithdraweableDelegatedTokens(delegation);
        require(tokensToWithdraw > 0, "!tokens");

        // Reset lock
        delegation.tokensLocked = 0;
        delegation.tokensLockedUntil = 0;

        emit StakeDelegatedWithdrawn(_indexer, _delegator, tokensToWithdraw);

        // -- Interactions --

        if (_delegateToIndexer != address(0)) {
            // Re-delegate tokens to a new indexer
            _delegate(_delegator, _delegateToIndexer, tokensToWithdraw);
        } else {
            // Return tokens to the delegator
            require(graphToken().transfer(_delegator, tokensToWithdraw), "!transfer");
        }

        return tokensToWithdraw;
    }

    /**
     * @dev Collect the delegation rewards for query fees.
     * This function will assign the collected fees to the delegation pool.
     * @param _indexer Indexer to which the tokens to distribute are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of delegation rewards
     */
    function _collectDelegationQueryRewards(address _indexer, uint256 _tokens)
        private
        returns (uint256)
    {
        uint256 delegationRewards = 0;
        DelegationPool storage pool = delegationPools[_indexer];
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
    function _collectDelegationIndexingRewards(address _indexer, uint256 _tokens)
        private
        returns (uint256)
    {
        uint256 delegationRewards = 0;
        DelegationPool storage pool = delegationPools[_indexer];
        if (pool.tokens > 0 && pool.indexingRewardCut < MAX_PPM) {
            uint256 indexerCut = uint256(pool.indexingRewardCut).mul(_tokens).div(MAX_PPM);
            delegationRewards = _tokens.sub(indexerCut);
            pool.tokens = pool.tokens.add(delegationRewards);
        }
        return delegationRewards;
    }

    /**
     * @dev Collect the curation fees for a subgraph deployment from an amount of tokens.
     * @param _subgraphDeploymentID Subgraph deployment to which the curation fees are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of curation fees
     */
    function _collectCurationFees(bytes32 _subgraphDeploymentID, uint256 _tokens)
        private
        view
        returns (uint256)
    {
        ICuration curation = curation();
        bool isCurationEnabled = curationPercentage > 0 && address(curation) != address(0);
        if (isCurationEnabled && curation.isCurated(_subgraphDeploymentID)) {
            return uint256(curationPercentage).mul(_tokens).div(MAX_PPM);
        }
        return 0;
    }

    /**
     * @dev Calculate the protocol fees to be burned for an amount of tokens.
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of protocol fees
     */
    function _collectProtocolFees(uint256 _tokens) private view returns (uint256) {
        if (protocolPercentage == 0) {
            return 0;
        }
        return uint256(protocolPercentage).mul(_tokens).div(MAX_PPM);
    }

    /**
     * @dev Calculate the delegation tax to be burned for an amount of tokens.
     * @param _tokens Total tokens received used to calculate the amount of tax to collect
     * @return Amount of delegation tax
     */
    function _collectDelegationTax(uint256 _tokens) private view returns (uint256) {
        if (delegationTaxPercentage == 0) {
            return 0;
        }
        return uint256(delegationTaxPercentage).mul(_tokens).div(MAX_PPM);
    }

    /**
     * @dev Return the current state of an allocation
     * @param _allocationID Allocation identifier
     * @return AllocationState
     */
    function _getAllocationState(address _allocationID) private view returns (AllocationState) {
        Allocation memory alloc = allocations[_allocationID];

        if (alloc.indexer == address(0)) {
            return AllocationState.Null;
        }
        if (alloc.tokens == 0) {
            return AllocationState.Claimed;
        }
        if (alloc.closedAtEpoch == 0) {
            return AllocationState.Active;
        }

        uint256 epochs = epochManager().epochsSince(alloc.closedAtEpoch);
        if (epochs >= channelDisputeEpochs) {
            return AllocationState.Finalized;
        }
        return AllocationState.Closed;
    }

    /**
     * @dev Get the effective stake allocation considering epochs from allocation to closing.
     * @param _tokens Amount of tokens allocated
     * @param _numEpochs Number of epochs that passed from allocation to closing
     * @return Effective allocated tokens accross epochs
     */
    function _getEffectiveAllocation(uint256 _tokens, uint256 _numEpochs)
        private
        view
        returns (uint256)
    {
        bool shouldCap = maxAllocationEpochs > 0 && _numEpochs > maxAllocationEpochs;
        return _tokens.mul((shouldCap) ? maxAllocationEpochs : _numEpochs);
    }

    /**
     * @dev Triggers an update of rewards due to a change in allocations.
     * @param _subgraphDeploymentID Subgrapy deployment updated
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

        // Add the rest of the rewards to the indexer stake
        if (indexerRewards > 0) {
            _stake(_indexer, indexerRewards);
        }
    }

    /**
     * @dev Burn tokens held by this contract.
     * @param _amount Amount of tokens to burn
     */
    function _burnTokens(uint256 _amount) private {
        if (_amount > 0) {
            graphToken().burn(_amount);
        }
    }
}
