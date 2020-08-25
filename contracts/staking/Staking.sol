pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "../upgrades/GraphProxy.sol";
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
     * `channelPubKey` is the public key used for routing payments to the indexer channel.
     * `price` price the `indexer` will charge for serving queries of the `subgraphDeploymentID`.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address allocationID,
        bytes channelPubKey,
        uint256 price,
        address assetHolder
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
     * @dev Emitted when `indexer` settled an allocation in `epoch` for `allocationID`.
     * An amount of `tokens` get unallocated from `subgraphDeploymentID`.
     * The `effectiveAllocation` are the tokens allocated from creation to settlement.
     * This event also emits the POI (proof of indexing) submitted by the indexer.
     */
    event AllocationSettled(
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
     * The rebate is for `tokens` amount and an outstanding `settlements` are left for claim
     * in the rebate pool. `delegationFees` collected and sent to delegation pool.
     */
    event RebateClaimed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        address allocationID,
        uint256 epoch,
        uint256 forEpoch,
        uint256 tokens,
        uint256 settlements,
        uint256 delegationFees
    );

    /**
     * @dev Emitted when `caller` set `slasher` address as `enabled` to slash stakes.
     */
    event SlasherUpdate(address indexed caller, address indexed slasher, bool enabled);

    /**
     * @dev Emitted when `indexer` set `operator` access.
     */
    event SetOperator(address indexed indexer, address operator, bool allowed);

    /**
     * @dev Check if the caller is the slasher.
     */
    modifier onlySlasher {
        require(slashers[msg.sender] == true, "Caller is not a Slasher");
        _;
    }

    /**
     * @dev Check if the caller is authorized (indexer or operator)
     */
    function _onlyAuth(address _indexer) internal view returns (bool) {
        return msg.sender == _indexer || operatorAuth[_indexer][msg.sender] == true;
    }

    /**
     * @dev Check if the caller is authorized (indexer, operator or delegator)
     */
    function _onlyAuthOrDelegator(address _indexer) internal view returns (bool) {
        return _onlyAuth(_indexer) || delegationPools[_indexer].delegators[msg.sender].shares > 0;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     * @param _controller Controller for this contract
     */
    function acceptProxy(GraphProxy _proxy, address _controller) external {
        // Accept to be the implementation for this proxy
        _acceptUpgrade(_proxy);

        // Initialization
        Staking(address(_proxy)).initialize(_controller);
    }

    /**
     * @dev Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function setThawingPeriod(uint32 _thawingPeriod) external override onlyGovernor {
        thawingPeriod = _thawingPeriod;
        emit ParameterUpdated("thawingPeriod");
    }

    /**
     * @dev Set the curation percentage of query fees sent to curators.
     * @param _percentage Percentage of query fees sent to curators
     */
    function setCurationPercentage(uint32 _percentage) external override onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Curation percentage must be below or equal to MAX_PPM");
        curationPercentage = _percentage;
        emit ParameterUpdated("curationPercentage");
    }

    /**
     * @dev Set a protocol percentage to burn when collecting query fees.
     * @param _percentage Percentage of query fees to burn as protocol fee
     */
    function setProtocolPercentage(uint32 _percentage) external override onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Protocol percentage must be below or equal to MAX_PPM");
        protocolPercentage = _percentage;
        emit ParameterUpdated("protocolPercentage");
    }

    /**
     * @dev Set the period in epochs that need to pass before fees in rebate pool can be claimed.
     * @param _channelDisputeEpochs Period in epochs
     */
    function setChannelDisputeEpochs(uint32 _channelDisputeEpochs) external override onlyGovernor {
        channelDisputeEpochs = _channelDisputeEpochs;
        emit ParameterUpdated("channelDisputeEpochs");
    }

    /**
     * @dev Set the max time allowed for indexers stake on allocations.
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function setMaxAllocationEpochs(uint32 _maxAllocationEpochs) external override onlyGovernor {
        maxAllocationEpochs = _maxAllocationEpochs;
        emit ParameterUpdated("maxAllocationEpochs");
    }

    /**
     * @dev Set the delegation capacity multiplier.
     * @param _delegationCapacity Delegation capacity multiplier
     */
    function setDelegationCapacity(uint32 _delegationCapacity) external override onlyGovernor {
        delegationCapacity = _delegationCapacity;
        emit ParameterUpdated("delegationCapacity");
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
    ) external override {
        address indexer = msg.sender;

        // Incentives must be within bounds
        require(
            _queryFeeCut <= MAX_PPM,
            "Delegation: QueryFeeCut must be below or equal to MAX_PPM"
        );
        require(
            _indexingRewardCut <= MAX_PPM,
            "Delegation: IndexingRewardCut must be below or equal to MAX_PPM"
        );

        // Cooldown period set by indexer cannot be below protocol global setting
        require(
            _cooldownBlocks >= delegationParametersCooldown,
            "Delegation: cooldown cannot be below minimum"
        );

        // Verify the cooldown period passed
        DelegationPool storage pool = delegationPools[indexer];
        require(
            pool.updatedAtBlock == 0 ||
                pool.updatedAtBlock.add(uint256(pool.cooldownBlocks)) <= block.number,
            "Delegation: must expire cooldown period to update parameters"
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
        delegationUnbondingPeriod = _delegationUnbondingPeriod;
        emit ParameterUpdated("delegationUnbondingPeriod");
    }

    /**
     * @dev Set an address as allowed slasher.
     * @param _slasher Address of the party allowed to slash indexers
     * @param _allowed True if slasher is allowed
     */
    function setSlasher(address _slasher, bool _allowed) external override onlyGovernor {
        slashers[_slasher] = _allowed;
        emit SlasherUpdate(msg.sender, _slasher, _allowed);
    }

    /**
     * @dev Get the GRT token used by the contract.
     * @return GRT token contract address
     */
    function token() public view returns (IGraphToken) {
        return graphToken();
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
     * @dev Get the amount of shares a delegator has in a delegation pool.
     * @param _indexer Address of the indexer
     * @param _delegator Address of the delegator
     * @return Shares owned by delegator in a delegation pool
     */
    function getDelegationShares(address _indexer, address _delegator)
        external
        override
        view
        returns (uint256)
    {
        return delegationPools[_indexer].delegators[_delegator].shares;
    }

    /**
     * @dev Get the amount of tokens a delegator has in a delegation pool.
     * @param _indexer Address of the indexer
     * @param _delegator Address of the delegator
     * @return Tokens owned by delegator in a delegation pool
     */
    function getDelegationTokens(address _indexer, address _delegator)
        external
        override
        view
        returns (uint256)
    {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        if (pool.shares == 0) {
            return 0;
        }
        uint256 _shares = delegationPools[_indexer].delegators[_delegator].shares;
        return _shares.mul(pool.tokens).div(pool.shares);
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
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerCapacity(address _indexer) public override view returns (uint256) {
        Stakes.Indexer memory indexerStake = stakes[_indexer];
        DelegationPool memory pool = delegationPools[_indexer];

        uint256 tokensDelegatedMax = indexerStake.tokensStaked.mul(uint256(delegationCapacity));
        uint256 tokensDelegated = (pool.tokens < tokensDelegatedMax)
            ? pool.tokens
            : tokensDelegatedMax;

        uint256 tokensUsed = indexerStake.tokensUsed();
        uint256 tokensCapacity = indexerStake.tokensStaked.add(tokensDelegated);

        // If more tokens are used than the current capacity, the indexer is overallocated.
        // This means the indexer doesn't have available capacity to create new allocations.
        // We can reach this state when the indexer has funds allocated and then any
        // of these conditions happen:
        // - The delegationCapacity ratio is reduced.
        // - The indexer stake is slashed.
        // - A delegator removes enough stake.
        if (tokensUsed > tokensCapacity) {
            return 0;
        }
        return tokensCapacity.sub(tokensUsed);
    }

    /**
     * @dev Authorize an address to be an operator.
     * @param _operator Address to authorize
     * @param _allowed Whether authorized or not
     */
    function setOperator(address _operator, bool _allowed) external override {
        operatorAuth[msg.sender][_operator] = _allowed;
        emit SetOperator(msg.sender, _operator, _allowed);
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
    function stakeTo(address _indexer, uint256 _tokens) public override {
        require(_tokens > 0, "Staking: cannot stake zero tokens");

        // Transfer tokens to stake from caller to this contract
        require(
            graphToken().transferFrom(msg.sender, address(this), _tokens),
            "Staking: cannot transfer tokens to stake"
        );

        // Stake the transferred tokens
        _stake(_indexer, _tokens);
    }

    /**
     * @dev Unstake tokens from the indexer stake, lock them until thawing period expires.
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external override {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        require(indexerStake.hasTokens(), "Staking: indexer has no stakes");
        require(
            indexerStake.tokensAvailable() >= _tokens,
            "Staking: not enough tokens available to unstake"
        );

        indexerStake.lockTokens(_tokens, thawingPeriod);

        emit StakeLocked(indexer, indexerStake.tokensLocked, indexerStake.tokensLockedUntil);
    }

    /**
     * @dev Withdraw indexer tokens once the thawing period has passed.
     */
    function withdraw() external override {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        // Get tokens available for withdraw and update balance
        uint256 tokensToWithdraw = indexerStake.withdrawTokens();
        require(tokensToWithdraw > 0, "Staking: no tokens available to withdraw");

        // Return tokens to the indexer
        require(
            graphToken().transfer(indexer, tokensToWithdraw),
            "Staking: cannot transfer tokens"
        );

        emit StakeWithdrawn(indexer, tokensToWithdraw);
    }

    /**
     * @dev Slash the indexer stake.
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
    ) external override onlySlasher {
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        // Only able to slash a non-zero number of tokens
        require(_tokens > 0, "Slashing: cannot slash zero tokens");

        // Rewards comes from tokens slashed balance
        require(_tokens >= _reward, "Slashing: reward cannot be higher than slashed amount");

        // Cannot slash stake of an indexer without any or enough stake
        require(indexerStake.hasTokens(), "Slashing: indexer has no stakes");
        require(
            _tokens <= indexerStake.tokensStaked,
            "Slashing: cannot slash more than staked amount"
        );

        // Validate beneficiary of slashed tokens
        require(_beneficiary != address(0), "Slashing: beneficiary must not be an empty address");

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

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        uint256 tokensToBurn = _tokens.sub(_reward);
        if (tokensToBurn > 0) {
            graphToken().burn(tokensToBurn);
        }

        // Give the beneficiary a reward for slashing
        if (_reward > 0) {
            require(
                graphToken().transfer(_beneficiary, _reward),
                "Slashing: error sending dispute reward"
            );
        }

        emit StakeSlashed(_indexer, _tokens, _reward, _beneficiary);
    }

    /**
     * @dev Delegate tokens to an indexer.
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     */
    function delegate(address _indexer, uint256 _tokens) external override {
        address delegator = msg.sender;

        // Transfer tokens to delegate to this contract
        require(
            graphToken().transferFrom(delegator, address(this), _tokens),
            "Delegation: Cannot transfer tokens to stake"
        );

        // Update state
        _delegate(delegator, _indexer, _tokens);
    }

    /**
     * @dev Undelegate tokens from an indexer.
     * @param _indexer Address of the indexer where tokens had been delegated
     * @param _shares Amount of shares to return and undelegate tokens
     */
    function undelegate(address _indexer, uint256 _shares) external override {
        _undelegate(msg.sender, _indexer, _shares);
    }

    /**
     * @dev Withdraw delegated tokens once the unbonding period has passed.
     * @param _indexer Withdraw available tokens delegated to indexer
     * @param _newIndexer Re-delegate to indexer address if non-zero, withdraw if zero address
     */
    function withdrawDelegated(address _indexer, address _newIndexer) external override {
        address delegator = msg.sender;

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[delegator];

        // There must be locked tokens and period passed
        uint256 currentEpoch = epochManager().currentEpoch();
        require(
            delegation.tokensLockedUntil > 0 && currentEpoch >= delegation.tokensLockedUntil,
            "Delegation: no tokens available to withdraw"
        );

        // Get tokens available for withdrawal
        uint256 tokensToWithdraw = delegation.tokensLocked;

        // Reset lock
        delegation.tokensLocked = 0;
        delegation.tokensLockedUntil = 0;

        emit StakeDelegatedWithdrawn(_indexer, delegator, tokensToWithdraw);

        if (_newIndexer != address(0)) {
            // Re-delegate tokens to a new indexer
            _delegate(delegator, _newIndexer, tokensToWithdraw);
        } else {
            // Return tokens to the delegator
            require(
                graphToken().transfer(delegator, tokensToWithdraw),
                "Delegation: cannot transfer tokens"
            );
        }
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used to route payments
     * @param _assetHolder Authorized sender address of collected funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _assetHolder,
        uint256 _price
    ) external override {
        require(_onlyAuth(msg.sender), "Allocation: caller must be authorized");

        _allocate(msg.sender, _subgraphDeploymentID, _tokens, _channelPubKey, _assetHolder, _price);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used to route payments
     * @param _assetHolder Authorized sender address of collected funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function allocateFrom(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _assetHolder,
        uint256 _price
    ) external override {
        require(_onlyAuth(_indexer), "Allocation: caller must be authorized");

        _allocate(_indexer, _subgraphDeploymentID, _tokens, _channelPubKey, _assetHolder, _price);
    }

    /**
     * @dev Settle an allocation and free the staked tokens.
     * @param _allocationID The allocation identifier
     * @param _poi Proof of indexing submitted for the allocated period
     */
    function settle(address _allocationID, bytes32 _poi) external override {
        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // Allocation must exist and be active
        require(allocState == AllocationState.Active, "Settle: allocation must be active");

        // Get indexer stakes
        Stakes.Indexer storage indexerStake = stakes[alloc.indexer];

        // Validate that an allocation cannot be settled before one epoch
        uint256 currentEpoch = epochManager().currentEpoch();
        uint256 epochs = alloc.createdAtEpoch < currentEpoch
            ? currentEpoch.sub(alloc.createdAtEpoch)
            : 0;
        require(epochs > 0, "Settle: must pass at least one epoch");

        // Validate ownership
        if (epochs > maxAllocationEpochs) {
            // Verify that the allocation owner or delegator is settling
            require(_onlyAuthOrDelegator(alloc.indexer), "Settle: caller must be authorized");
        } else {
            // Verify that the allocation owner is settling
            require(_onlyAuth(alloc.indexer), "Settle: caller must be authorized");
        }

        // Settle the allocation and start counting a period to finalize any other
        // withdrawal.
        alloc.settledAtEpoch = currentEpoch;
        alloc.effectiveAllocation = _getEffectiveAllocation(alloc.tokens, epochs);

        // Send funds to rebate pool and account the effective allocation
        Rebates.Pool storage rebatePool = rebates[currentEpoch];
        rebatePool.addToPool(alloc.collectedFees, alloc.effectiveAllocation);

        // Assign rewards
        _assignRewards(_allocationID);

        // Free allocated tokens from use
        indexerStake.unallocate(alloc.tokens);

        // Track total allocations per subgraph
        // Used for rewards calculations
        subgraphAllocations[alloc.subgraphDeploymentID] = subgraphAllocations[alloc
            .subgraphDeploymentID]
            .sub(alloc.tokens);

        emit AllocationSettled(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            alloc.settledAtEpoch,
            alloc.tokens,
            _allocationID,
            alloc.effectiveAllocation,
            msg.sender,
            _poi
        );
    }

    /**
     * @dev Collect query fees for an allocation.
     * Funds received are only accepted from a valid source.
     * @param _tokens Amount of tokens to collect
     */
    function collect(uint256 _tokens, address _allocationID) external override {
        // Allocation identifier validation
        require(_allocationID != address(0), "Collect: invalid allocation");

        // NOTE: commented out for easier test of state-channel integrations
        // NOTE: this validation might be removed in the future if no harm to the
        // NOTE: economic incentive structure is done by an external caller use
        // NOTE: of this function
        // The contract caller must be an asset holder registered during allocate()
        // Allocation memory alloc = allocations[_allocationID];
        // require(alloc.assetHolder == msg.sender, "Collect: caller is not authorized");

        // Transfer tokens to collect from the authorized sender
        require(
            graphToken().transferFrom(msg.sender, address(this), _tokens),
            "Collect: cannot transfer tokens to collect"
        );

        _collect(_allocationID, msg.sender, _tokens);
    }

    /**
     * @dev Claim tokens from the rebate pool.
     * @param _allocationID Allocation from where we are claiming tokens
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claim(address _allocationID, bool _restake) external override {
        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // Validate ownership
        require(_onlyAuthOrDelegator(alloc.indexer), "Rebate: caller must be authorized");

        // TODO: restake when delegator called should not be allowed?

        // Funds can only be claimed after a period of time passed since settlement
        require(
            allocState == AllocationState.Finalized,
            "Rebate: allocation must be in finalized state"
        );

        // Find a rebate pool for the settled epoch
        Rebates.Pool storage pool = rebates[alloc.settledAtEpoch];

        // Process rebate
        uint256 tokensToClaim = pool.redeem(alloc.collectedFees, alloc.effectiveAllocation);

        // When all settlements processed then prune rebate pool
        if (pool.settlementsCount == 0) {
            delete rebates[alloc.settledAtEpoch];
        }

        // Calculate delegation fees and add them to the delegation pool
        uint256 delegationFees = _collectDelegationFees(alloc.indexer, tokensToClaim);
        tokensToClaim = tokensToClaim.sub(delegationFees);

        // Purge allocation data except for:
        // - indexer: used in disputes and to avoid reusing an allocationID
        // - subgraphDeploymentID: used in disputes
        uint256 settledAtEpoch = alloc.settledAtEpoch;
        alloc.tokens = 0; // This avoid collect(), settle() and claim() to be called
        alloc.createdAtEpoch = 0;
        alloc.settledAtEpoch = 0;
        alloc.collectedFees = 0;
        alloc.effectiveAllocation = 0;
        alloc.assetHolder = address(0); // This avoid collect() to be called

        // When there are tokens to claim from the rebate pool, transfer or restake
        if (tokensToClaim > 0) {
            // Assign claimed tokens
            if (_restake) {
                // Restake to place fees into the indexer stake
                _stake(alloc.indexer, tokensToClaim);
            } else {
                // Transfer funds back to the indexer
                require(
                    graphToken().transfer(alloc.indexer, tokensToClaim),
                    "Rebate: cannot transfer tokens"
                );
            }
        }

        emit RebateClaimed(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            _allocationID,
            epochManager().currentEpoch(),
            settledAtEpoch,
            tokensToClaim,
            pool.settlementsCount,
            delegationFees
        );
    }

    /**
     * @dev Stake tokens on the indexer
     * @param _indexer Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexer, uint256 _tokens) internal {
        // Deposit tokens into the indexer stake
        Stakes.Indexer storage indexerStake = stakes[_indexer];
        indexerStake.deposit(_tokens);

        // Initialize the delegation pool the first time
        DelegationPool storage pool = delegationPools[_indexer];
        if (pool.updatedAtBlock == 0) {
            pool.indexingRewardCut = MAX_PPM;
            pool.queryFeeCut = MAX_PPM;
            pool.updatedAtBlock = block.number;
        }

        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used by the indexer to setup the off-chain channel
     * @param _assetHolder Authorized sender address of collected funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function _allocate(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes memory _channelPubKey,
        address _assetHolder,
        uint256 _price
    ) internal {
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        // Only allocations with a non-zero token amount are allowed
        require(_tokens > 0, "Allocation: cannot allocate zero tokens");

        // Channel public key must be in uncompressed format
        require(
            uint8(_channelPubKey[0]) == 4 && _channelPubKey.length == 65,
            "Allocation: invalid channel public key"
        );

        // Needs to have free capacity not used for other purposes to allocate
        require(
            getIndexerCapacity(_indexer) >= _tokens,
            "Allocation: not enough tokens available to allocate"
        );

        // A channel public key is derived by the indexer when creating the offchain payment channel.
        // Get the Ethereum address from the public key and use as allocation identifier.
        // The allocationID will work to identify collected funds related to this allocation.
        address allocationID = address(uint256(keccak256(_sliceByte(bytes(_channelPubKey)))));

        // Cannot reuse an allocationID that has already been used in an allocation
        require(
            _getAllocationState(allocationID) == AllocationState.Null,
            "Allocation: allocationID already used"
        );

        // Creates an allocation
        // Allocation identifiers are not reused
        // The authorized sender address can send collected funds to the allocation
        Allocation memory alloc = Allocation(
            _indexer,
            _subgraphDeploymentID,
            _tokens, // Tokens allocated
            epochManager().currentEpoch(), // createdAtEpoch
            0, // settledAtEpoch
            0, // Initialize collected fees
            0, // Initialize effective allocation
            _assetHolder, // Source address for allocation collected funds
            _updateRewards(_subgraphDeploymentID) // Initialize accumulated rewards per stake allocated
        );
        allocations[allocationID] = alloc;

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
            allocationID,
            _channelPubKey,
            _price,
            _assetHolder
        );
    }

    /**
     * @dev Withdraw and collect funds for an allocation.
     * @param _allocationID Allocation that is receiving collected funds
     * @param _from Source of collected funds for the allocation
     * @param _tokens Amount of tokens to withdraw
     */
    function _collect(
        address _allocationID,
        address _from,
        uint256 _tokens
    ) internal {
        uint256 rebateFees = _tokens;

        // Get allocation
        Allocation storage alloc = allocations[_allocationID];
        AllocationState allocState = _getAllocationState(_allocationID);

        // The allocation must be active or settled
        require(
            allocState == AllocationState.Active || allocState == AllocationState.Settled,
            "Collect: allocation must be active or settled"
        );

        // Collect protocol fees to be burned
        uint256 protocolFees = _collectProtocolFees(rebateFees);
        rebateFees = rebateFees.sub(protocolFees);

        // Calculate curation fees only if the subgraph deployment is curated
        uint256 curationFees = _collectCurationFees(alloc.subgraphDeploymentID, rebateFees);
        rebateFees = rebateFees.sub(curationFees);

        // Collect funds for the allocation
        alloc.collectedFees = alloc.collectedFees.add(rebateFees);

        // When allocation is settled redirect funds to the rebate pool
        // This way we can keep collecting tokens even after settlement until the allocation
        // gets to the finalized state.
        if (allocState == AllocationState.Settled) {
            Rebates.Pool storage rebatePool = rebates[alloc.settledAtEpoch];
            rebatePool.fees = rebatePool.fees.add(rebateFees);
        }

        // TODO: for consistency we could burn protocol fees here

        // Send curation fees to the curator reserve pool
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            ICuration curation = curation();
            require(
                graphToken().approve(address(curation), curationFees),
                "Collect: token approval failed"
            );
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
            rebateFees
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
    ) internal returns (uint256) {
        // Can only delegate a non-zero amount of tokens
        require(_tokens > 0, "Delegation: cannot delegate zero tokens");
        // Can only delegate to non-empty address
        require(_indexer != address(0), "Delegation: cannot delegate to empty address");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? _tokens : _tokens.mul(pool.shares).div(pool.tokens);

        // Update the delegation pool
        pool.tokens = pool.tokens.add(_tokens);
        pool.shares = pool.shares.add(shares);

        // Update the delegation
        delegation.shares = delegation.shares.add(shares);

        emit StakeDelegated(_indexer, _delegator, _tokens, shares);

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
    ) internal returns (uint256) {
        // Can only undelegate a non-zero amount of shares
        require(_shares > 0, "Delegation: cannot undelegate zero shares");

        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegationPools[_indexer];
        Delegation storage delegation = pool.delegators[_delegator];

        // Delegator need to have enough shares in the pool to undelegate
        require(delegation.shares >= _shares, "Delegation: delegator does not have enough shares");

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
     * @dev Collect the delegation fees related to an indexer from an amount of tokens.
     * This function will also assign the collected fees to the delegation pool.
     * @param _indexer Indexer to which the delegation fees are related
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of delegation fees
     */
    function _collectDelegationFees(address _indexer, uint256 _tokens) internal returns (uint256) {
        uint256 delegationFees = 0;
        DelegationPool storage pool = delegationPools[_indexer];
        if (pool.tokens > 0 && pool.queryFeeCut < MAX_PPM) {
            uint256 indexerCut = uint256(pool.queryFeeCut).mul(_tokens).div(MAX_PPM);
            delegationFees = _tokens.sub(indexerCut);
            pool.tokens = pool.tokens.add(delegationFees);
        }
        return delegationFees;
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
     * @dev Collect and burn the protocol fees for an amount of tokens.
     * @param _tokens Total tokens received used to calculate the amount of fees to collect
     * @return Amount of protocol fees
     */
    function _collectProtocolFees(uint256 _tokens) internal returns (uint256) {
        if (protocolPercentage == 0) {
            return 0;
        }
        uint256 protocolFees = uint256(protocolPercentage).mul(_tokens).div(MAX_PPM);
        if (protocolFees > 0) {
            graphToken().burn(protocolFees);
        }
        return protocolFees;
    }

    /**
     * @dev Return the current state of an allocation
     * @param _allocationID Allocation identifier
     * @return AllocationState
     */
    function _getAllocationState(address _allocationID) internal view returns (AllocationState) {
        Allocation memory alloc = allocations[_allocationID];

        if (alloc.indexer == address(0)) {
            return AllocationState.Null;
        }
        if (alloc.tokens == 0) {
            return AllocationState.Claimed;
        }
        if (alloc.settledAtEpoch == 0) {
            return AllocationState.Active;
        }

        uint256 epochs = epochManager().epochsSince(alloc.settledAtEpoch);
        if (epochs >= channelDisputeEpochs) {
            return AllocationState.Finalized;
        }
        return AllocationState.Settled;
    }

    /**
     * @dev Get the effective stake allocation considering epochs from allocation to settlement.
     * @param _tokens Amount of tokens allocated
     * @param _numEpochs Number of epochs that passed from allocation to settlement
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
     * @dev Get the running network chain ID
     * @return The chain ID
     */
    function _getChainID() internal pure returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * @dev Removes the first byte from a bytes array.
     * @param _bytes Byte array to slice
     * @return New bytes array
     */
    function _sliceByte(bytes memory _bytes) internal pure returns (bytes memory) {
        bytes memory tempBytes;
        uint256 length = _bytes.length - 1;

        assembly {
            tempBytes := mload(0x40)

            let lengthmod := and(length, 31)
            let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
            let end := add(mc, length)

            for {
                let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), 1)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            mstore(tempBytes, length)
            mstore(0x40, and(add(mc, 31), not(31)))
        }

        return tempBytes;
    }

    /**
     * @dev Triggers an update of rewards due to a change in allocations.
     * @param _subgraphDeploymentID Subgrapy deployment updated
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) internal returns (uint256) {
        IRewardsManager rewardsManager = rewardsManager();
        if (address(rewardsManager) == address(0)) {
            return 0;
        }
        return rewardsManager.onSubgraphAllocationUpdate(_subgraphDeploymentID);
    }

    /**
     * @dev Assign rewards for the settled allocation to the indexer.
     * @param _allocationID Allocation
     */
    function _assignRewards(address _allocationID) internal returns (uint256) {
        IRewardsManager rewardsManager = rewardsManager();
        if (address(rewardsManager) == address(0)) {
            return 0;
        }
        // Automatically triggers update of rewards snapshot as allocation will change
        return rewardsManager.assignRewards(_allocationID);
    }
}
