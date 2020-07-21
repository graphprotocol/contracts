pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@nomiclabs/buidler/console.sol";

import "../EpochManager.sol";
import "../curation/ICuration.sol";
import "../governance/Governed.sol";
import "../token/IGraphToken.sol";
import "../upgrades/GraphProxy.sol";

import "./IStaking.sol";
import "./StakingStorage.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

/**
 * @title Staking contract
 */
contract Staking is StakingV1Storage, IStaking, Governed {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;
    using Rebates for Rebates.Pool;

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

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
     * `channelID` is the address of the indexer in the channel multisig.
     * `channelPubKey` is the public key used for routing payments to the indexer channel.
     * `price` price the `indexer` will charge for serving queries of the `subgraphDeploymentID`.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address channelID,
        bytes channelPubKey,
        uint256 price
    );

    /**
     * @dev Emitted when `indexer` withdrew `tokens` amount in `epoch` from `channelID` channel.
     * The funds are related to `subgraphDeploymentID`.
     * `from` attribute records the the multisig contract from where it was settled.
     */
    event AllocationCollected(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address channelID,
        address from,
        uint256 curationFees,
        uint256 rebateFees
    );

    /**
     * @dev Emitted when `indexer` settled an allocation in `epoch` for `channelID` channel.
     * The `tokens` getting unallocated from `subgraphDeploymentID`.
     * The `effectiveAllocation` are the tokens allocated from creation to settlement.
     */
    event AllocationSettled(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 tokens,
        address channelID,
        uint256 effectiveAllocation
    );

    /**
     * @dev Emitted when `indexer` claimed a rebate on `subgraphDeploymentID` during `epoch`
     * related to the `forEpoch` rebate pool.
     * The rebate is for `tokens` amount and an outstanding `settlements` count are
     * left for claim in the rebate pool. `delegationFees` collected and sent to delegation pool.
     */
    event RebateClaimed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
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
     * @dev Check if the caller is the governor or initializing the implementation.
     */
    modifier onlyGovernorOrInit {
        require(msg.sender == governor || msg.sender == implementation, "Only Governor can call");
        _;
    }

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
    function _onlyAuth(address _indexer) private view returns (bool) {
        return msg.sender == _indexer || operatorAuth[_indexer][msg.sender] == true;
    }

    /**
     * @dev Check if the caller is authorized (indexer, operator or delegator)
     */
    function _onlyAuthOrDelegator(address _indexer) private view returns (bool) {
        return _onlyAuth(_indexer) || delegationPools[_indexer].delegators[msg.sender].shares > 0;
    }

    /**
     * @dev Staking Contract Constructor.
     * @param _token Address of the Graph Protocol token
     * @param _epochManager Address of the EpochManager contract
     */
    function initialize(address _token, address _epochManager) external onlyGovernorOrInit {
        token = IGraphToken(_token);
        epochManager = EpochManager(_epochManager);
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     * @param _token Address of the Graph Protocol token
     * @param _epochManager Address of the EpochManager contract
     */
    function acceptUpgrade(
        GraphProxy _proxy,
        address _token,
        address _epochManager
    ) external {
        require(msg.sender == _proxy.governor(), "Only proxy governor can upgrade");

        // Accept to be the implementation for this proxy
        _proxy.acceptImplementation();

        // Initialization
        Staking(address(_proxy)).initialize(_token, _epochManager);
    }

    /**
     * @dev Set the curation contract where to send curation fees.
     * @param _curation Address of the curation contract
     */
    function setCuration(address _curation) external override onlyGovernor {
        curation = ICuration(_curation);
        emit ParameterUpdated("curation");
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
     * @dev Set the max allocation time allowed for indexers stake on channels.
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
     * @dev Set the thawing period for unstaking.
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function setThawingPeriod(uint32 _thawingPeriod) external override onlyGovernor {
        thawingPeriod = _thawingPeriod;
        emit ParameterUpdated("thawingPeriod");
    }

    /**
     * @dev Return if channelID (address) was used as a channel in any allocation.
     * @param _channelID Address used as signer for indexer in channel
     * @return True if channelID already used
     */
    function isChannel(address _channelID) external override view returns (bool) {
        return _getAllocationState(_channelID) != AllocationState.Null;
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
     * @dev Return the allocation for a particular channel identifier.
     * @param _channelID Address used as channel identifier where stake has been allocated
     * @return Allocation data
     */
    function getAllocation(address _channelID) external override view returns (Allocation memory) {
        return allocations[_channelID];
    }

    /**
     * @dev Return the current state of an allocation.
     * @param _channelID Address used as the allocation channel identifier
     * @return AllocationState
     */
    function getAllocationState(address _channelID)
        external
        override
        view
        returns (AllocationState)
    {
        return _getAllocationState(_channelID);
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
        address indexer = msg.sender;

        require(_tokens > 0, "Staking: cannot stake zero tokens");

        // Transfer tokens to stake from indexer to this contract
        require(
            token.transferFrom(indexer, address(this), _tokens),
            "Staking: cannot transfer tokens to stake"
        );

        // Stake the transferred tokens
        _stake(indexer, _tokens);
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
        require(token.transfer(indexer, tokensToWithdraw), "Staking: cannot transfer tokens");

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
            token.burn(tokensToBurn);
        }

        // Give the beneficiary a reward for slashing
        if (_reward > 0) {
            require(
                token.transfer(_beneficiary, _reward),
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
            token.transferFrom(delegator, address(this), _tokens),
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
        uint256 currentEpoch = epochManager.currentEpoch();
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
                token.transfer(delegator, tokensToWithdraw),
                "Delegation: cannot transfer tokens"
            );
        }
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used by the indexer to setup the off-chain channel
     * @param _channelProxy Address of the multisig proxy used to hold channel funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _channelProxy,
        uint256 _price
    ) external override {
        require(_onlyAuth(msg.sender), "Allocation: caller must be authorized");

        _allocate(
            msg.sender,
            _subgraphDeploymentID,
            _tokens,
            _channelPubKey,
            _channelProxy,
            _price
        );
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used by the indexer to setup the off-chain channel
     * @param _channelProxy Address of the multisig proxy used to hold channel funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function allocateFrom(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes calldata _channelPubKey,
        address _channelProxy,
        uint256 _price
    ) external override {
        require(_onlyAuth(_indexer), "Allocation: caller must be authorized");

        _allocate(_indexer, _subgraphDeploymentID, _tokens, _channelPubKey, _channelProxy, _price);
    }

    /**
     * @dev Settle a channel and unallocate the staked tokens.
     * @param _channelID The channel identifier for the allocation
     */
    function settle(address _channelID) external override {
        // Get allocation related to the channel identifier
        Allocation storage alloc = allocations[_channelID];
        AllocationState allocState = _getAllocationState(_channelID);

        // Channel must exist and be allocated
        require(allocState == AllocationState.Active, "Settle: channel must be active");

        // Get indexer stakes
        Stakes.Indexer storage indexerStake = stakes[alloc.indexer];

        // Validate that an allocation cannot be settled before one epoch
        uint256 currentEpoch = epochManager.currentEpoch();
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
        // withdrawal from the related channel.
        alloc.settledAtEpoch = currentEpoch;
        alloc.effectiveAllocation = _getEffectiveAllocation(alloc.tokens, epochs);

        // Send funds to rebate pool and account the effective allocation
        Rebates.Pool storage rebatePool = rebates[currentEpoch];
        rebatePool.addToPool(alloc.collectedFees, alloc.effectiveAllocation);

        // Free allocated tokens from use
        indexerStake.unallocate(alloc.tokens);

        emit AllocationSettled(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            alloc.settledAtEpoch,
            alloc.tokens,
            _channelID,
            alloc.effectiveAllocation
        );
    }

    /**
     * @dev Collect query fees from a channel.
     * Funds received are only accepted from a channel multisig proxy contract.
     * @param _tokens Amount of tokens to collect
     */
    function collect(uint256 _tokens, address _channelID) external override {
        Allocation memory alloc = allocations[_channelID];

        // Channel identifier validation
        require(_channelID != address(0), "Collect: invalid channel");

        // The contract caller must be a channel proxy registered during allocation
        // The channelID must be related to the caller address
        require(
            alloc.channelProxy == msg.sender,
            "Collect: caller is not related to the channel allocation"
        );

        // Transfer tokens to collect from multisig to this contract
        require(
            token.transferFrom(msg.sender, address(this), _tokens),
            "Collect: cannot transfer tokens to settle"
        );

        _collect(_channelID, msg.sender, _tokens);
    }

    /**
     * @dev Claim tokens from the rebate pool.
     * @param _channelID Identifier of the channel we are claiming funds from
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claim(address _channelID, bool _restake) external override {
        // Get allocation related to the channel identifier
        Allocation storage alloc = allocations[_channelID];
        AllocationState allocState = _getAllocationState(_channelID);

        // Validate ownership
        require(_onlyAuthOrDelegator(alloc.indexer), "Rebate: caller must be authorized");

        // Funds can only be claimed after a period of time passed since settlement
        require(
            allocState == AllocationState.Finalized,
            "Rebate: channel must be in finalized state"
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

        // Purgue allocation data except for:
        // - indexer: used in disputes and to avoid reusing a channelID
        // - subgraphDeploymentID: used in disputes
        uint256 settledAtEpoch = alloc.settledAtEpoch;
        alloc.tokens = 0; // This avoid collect(), settle() and claim() to be called
        alloc.createdAtEpoch = 0;
        alloc.settledAtEpoch = 0;
        alloc.collectedFees = 0;
        alloc.effectiveAllocation = 0;
        alloc.channelProxy = address(0); // This avoid collect() to be called

        // When there are tokens to claim from the rebate pool, transfer or restake
        if (tokensToClaim > 0) {
            // Assign claimed tokens
            if (_restake) {
                // Restake to place fees into the indexer stake
                _stake(alloc.indexer, tokensToClaim);
            } else {
                // Transfer funds back to the indexer
                require(
                    token.transfer(alloc.indexer, tokensToClaim),
                    "Rebate: cannot transfer tokens"
                );
            }
        }

        emit RebateClaimed(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            epochManager.currentEpoch(),
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
    function _stake(address _indexer, uint256 _tokens) private {
        Stakes.Indexer storage indexerStake = stakes[_indexer];
        indexerStake.deposit(_tokens);
        emit StakeDeposited(_indexer, _tokens);
    }

    /**
     * @dev Allocate available tokens to a subgraph deployment.
     * @param _indexer Indexer address to allocate funds from.
     * @param _subgraphDeploymentID ID of the SubgraphDeployment where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used by the indexer to setup the off-chain channel
     * @param _channelProxy Address of the multisig proxy used to hold channel funds
     * @param _price Price the `indexer` will charge for serving queries of the `subgraphDeploymentID`
     */
    function _allocate(
        address _indexer,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        bytes memory _channelPubKey,
        address _channelProxy,
        uint256 _price
    ) private {
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
        // Get the Ethereum address from the public key and use as channel identifier.
        // The channel identifier is the address of the indexer signing party of a multisig that
        // will hold the funds received when the channel is settled.
        address channelID = address(uint256(keccak256(_sliceByte(bytes(_channelPubKey)))));

        // Cannot reuse a channelID that has already been used in an allocation
        require(
            _getAllocationState(channelID) == AllocationState.Null,
            "Allocation: channel ID already used"
        );

        // Create allocation linked to the channel identifier
        // Channel identifiers are not reused
        // The channel proxy address is the contract that will send tokens to be collected to
        // this contract
        allocations[channelID] = Allocation(
            _indexer,
            _subgraphDeploymentID,
            _tokens, // Tokens allocated
            epochManager.currentEpoch(), // createdAtEpoch
            0, // settledAtEpoch
            0, // Initialize with zero collected fees
            0, // Initialize effective allocation
            _channelProxy // Source address of channel funds
        );

        // Mark allocated tokens as used
        indexerStake.allocate(_tokens);

        emit AllocationCreated(
            _indexer,
            _subgraphDeploymentID,
            allocations[channelID].createdAtEpoch,
            allocations[channelID].tokens,
            channelID,
            _channelPubKey,
            _price
        );
    }

    /**
     * @dev Withdraw and collect funds from the channel.
     * @param _channelID ChannelID address of the indexer in the channel
     * @param _from Multisig channel address that triggered withdrawal
     * @param _tokens Amount of tokens to withdraw
     */
    function _collect(
        address _channelID,
        address _from,
        uint256 _tokens
    ) private {
        uint256 rebateFees = _tokens;

        // Get allocation related to the channel identifier
        Allocation storage alloc = allocations[_channelID];
        AllocationState allocState = _getAllocationState(_channelID);

        // The channel must be active or settled
        require(
            allocState == AllocationState.Active || allocState == AllocationState.Settled,
            "Collect: channel must be active or settled"
        );

        // Collect protocol fees to be burned
        uint256 protocolFees = _collectProtocolFees(rebateFees);
        rebateFees = rebateFees.sub(protocolFees);

        // Calculate curation fees only if the subgraph deployment is curated
        uint256 curationFees = _collectCurationFees(alloc.subgraphDeploymentID, rebateFees);
        rebateFees = rebateFees.sub(curationFees);

        // Collect funds in the allocated channel
        alloc.collectedFees = alloc.collectedFees.add(rebateFees);

        // When channel allocation is settling redirect funds to the rebate pool
        if (allocState == AllocationState.Settled) {
            Rebates.Pool storage rebatePool = rebates[alloc.settledAtEpoch];
            rebatePool.fees = rebatePool.fees.add(rebateFees);
        }

        // Send curation fees to the curator reserve pool
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            require(
                token.approve(address(curation), curationFees),
                "Collect: token approval failed"
            );
            curation.collect(alloc.subgraphDeploymentID, curationFees);
        }

        emit AllocationCollected(
            alloc.indexer,
            alloc.subgraphDeploymentID,
            epochManager.currentEpoch(),
            _tokens,
            _channelID,
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
    ) private returns (uint256) {
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
    ) private returns (uint256) {
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
        delegation.tokensLockedUntil = epochManager.currentEpoch().add(delegationUnbondingPeriod);

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
    function _collectDelegationFees(address _indexer, uint256 _tokens) private returns (uint256) {
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
    function _collectProtocolFees(uint256 _tokens) private returns (uint256) {
        if (protocolPercentage == 0) {
            return 0;
        }
        uint256 protocolFees = uint256(protocolPercentage).mul(_tokens).div(MAX_PPM);
        if (protocolFees > 0) {
            token.burn(protocolFees);
        }
        return protocolFees;
    }

    /**
     * @dev Return the current state of an allocation
     * @param _channelID Address used as the allocation channel identifier
     * @return AllocationState
     */
    function _getAllocationState(address _channelID) private view returns (AllocationState) {
        Allocation memory alloc = allocations[_channelID];

        if (alloc.indexer == address(0)) {
            return AllocationState.Null;
        }
        if (alloc.tokens == 0) {
            return AllocationState.Claimed;
        }
        if (alloc.settledAtEpoch == 0) {
            return AllocationState.Active;
        }

        uint256 epochs = epochManager.epochsSince(alloc.settledAtEpoch);
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
    function _getChainID() private pure returns (uint256) {
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
    function _sliceByte(bytes memory _bytes) private pure returns (bytes memory) {
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
}
