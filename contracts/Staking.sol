pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Curation.sol";
import "./EpochManager.sol";
import "./Governed.sol";
import "./GraphToken.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";

/**
 * @title Staking contract
 */
contract Staking is Governed {
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;
    using Stakes for Stakes.Allocation;
    using Rebates for Rebates.Pool;

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // -- Staking --

    // Time in blocks to unstake
    uint256 public thawingPeriod; // in blocks

    // Indexer stake tracking : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    // -- Allocation --

    struct Allocation {
        address indexer;
        bytes32 subgraphDeploymentID;
        uint256 tokens; // Tokens allocated to a SubgraphDeployment
        uint256 createdAtEpoch; // Epoch when it was created
        uint256 settledAtEpoch; // Epoch when it was settled
        uint256 collectedFees;
        uint256 effectiveAllocation;
    }

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public curationPercentage;

    // Need to pass this period to claim fees in rebate pool
    uint256 public channelDisputeEpochs;

    // Maximum allocation time
    uint256 public maxAllocationEpochs;

    // Allocations : allocationID => Allocation
    mapping(address => Allocation) allocations;

    // Channels Proxy : Channel Multisig Proxy => channelID
    mapping(address => address) public channelsProxy;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // -- Slashing --

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // -- Delegation --

    struct DelegationPool {
        uint256 cooldownBlocks;
        uint256 indexingRewardCut; // in PPM
        uint256 queryFeeCut; // in PPM
        uint256 updatedAtBlock;
        uint256 tokens;
        uint256 shares;
        mapping(address => uint256) delegatorShares; // Mapping of delegator => shares
    }

    // Set the delegation capacity multiplier.
    // If delegation capacity is 100 GRT, and an Indexer has staked 5 GRT,
    // then they can accept 500 GRT as delegated stake.
    uint256 public delegationCapacity;

    // Time in blocks an indexer needs to wait to change delegation parameters
    uint256 public delegationParametersCooldown;

    // Delegation pools : indexer => DelegationPool
    mapping(address => DelegationPool) public delegation;

    // -- Related contracts --

    GraphToken public token;
    EpochManager public epochManager;
    Curation public curation;

    // -- Events --

    /**
     * @dev Emitted when `indexer` update the delegation parameters for its delegation pool.
     */
    event DelegationParametersUpdated(
        address indexed indexer,
        uint256 indexingRewardCut,
        uint256 queryFeeCut,
        uint256 cooldownBlocks
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
     * @dev Emitted when `indexer` withdrew `tokens` staked.
     */
    event StakeWithdrawn(address indexed indexer, uint256 tokens);

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
     */
    event StakeUndelegated(
        address indexed indexer,
        address indexed delegator,
        uint256 tokens,
        uint256 shares
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
     * @dev Emitted when `indexer` settled an allocation of `tokens` amount to `subgraphDeploymentID`
     * during `epoch` using `channelID` as channel.
     *
     * NOTE: `from` tracks the multisig contract from where it was settled.
     */
    event AllocationSettled(
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

    modifier onlySlasher {
        require(slashers[msg.sender] == true, "Caller is not a Slasher");
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor Owner address of this contract
     * @param _token Address of the Graph Protocol token
     * @param _epochManager Address of the EpochManager contract
     */
    constructor(
        address _governor,
        address _token,
        address _epochManager
    ) public Governed(_governor) {
        token = GraphToken(_token);
        epochManager = EpochManager(_epochManager);
    }

    /**
     * @dev Set the curation contract where to send curation fees
     * @param _curation Address of the curation contract
     */
    function setCuration(address _curation) external onlyGovernor {
        curation = Curation(_curation);
        emit ParameterUpdated("curation");
    }

    /**
     * @dev Set the curation percentage of indexer fees sent to curators
     * @param _percentage Percentage of indexer fees sent to curators
     */
    function setCurationPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Curation percentage must be below or equal to MAX_PPM");
        curationPercentage = _percentage;
        emit ParameterUpdated("curationPercentage");
    }

    /**
     * @dev Set the period in epochs that need to pass before fees in rebate pool can be claimed
     * @param _channelDisputeEpochs Period in epochs
     */
    function setChannelDisputeEpochs(uint256 _channelDisputeEpochs) external onlyGovernor {
        channelDisputeEpochs = _channelDisputeEpochs;
        emit ParameterUpdated("channelDisputeEpochs");
    }

    /**
     * @dev Set the max allocation time allowed for indexers
     * @param _maxAllocationEpochs Allocation duration limit in epochs
     */
    function setMaxAllocationEpochs(uint256 _maxAllocationEpochs) external onlyGovernor {
        maxAllocationEpochs = _maxAllocationEpochs;
        emit ParameterUpdated("maxAllocationEpochs");
    }

    /**
     * @dev Set the time in blocks an indexer needs to wait to change delegation parameters.
     * @param _blocks Number of blocks to set the delegation parameters cooldown period
     */
    function setDelegationParametersCooldown(uint256 _blocks) external onlyGovernor {
        delegationParametersCooldown = _blocks;
        emit ParameterUpdated("delegationParametersCooldown");
    }

    /**
     * @dev Set the delegation capacity multiplier.
     * @param _delegationCapacity Delegation capacity multiplier
     */
    function setDelegationCapacity(uint256 _delegationCapacity) external onlyGovernor {
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
        uint256 _indexingRewardCut,
        uint256 _queryFeeCut,
        uint256 _cooldownBlocks
    ) external {
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
        DelegationPool storage pool = delegation[indexer];
        require(
            pool.updatedAtBlock == 0 ||
                pool.updatedAtBlock.add(pool.cooldownBlocks) <= block.number,
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
     * @dev Set an address as allowed slasher
     * @param _slasher Address of the party allowed to slash indexers
     * @param _allowed True if slasher is allowed
     */
    function setSlasher(address _slasher, bool _allowed) external onlyGovernor {
        slashers[_slasher] = _allowed;
        emit SlasherUpdate(msg.sender, _slasher, _allowed);
    }

    /**
     * @dev Set the thawing period for unstaking
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     */
    function setThawingPeriod(uint256 _thawingPeriod) external onlyGovernor {
        thawingPeriod = _thawingPeriod;
        emit ParameterUpdated("thawingPeriod");
    }

    /**
     * @dev Return if channelID (address) was used as a channel in any allocation.
     * @param _channelID Address used as signer for indexer in channel
     * @return True if channelID already used
     */
    function isChannel(address _channelID) public view returns (bool) {
        return allocations[_channelID].indexer != address(0);
    }

    /**
     * @dev Getter that returns if an indexer has any stake
     * @param _indexer Address of the indexer
     * @return True if indexer has staked tokens
     */
    function hasStake(address _indexer) public view returns (bool) {
        return stakes[_indexer].hasTokens();
    }

    /**
     * @dev Get the amount of shares a delegator has in a delegation pool
     * @param _indexer Address of the indexer
     * @param _delegator Address of the delegator
     * @return Shares owned by delegator in a delegation pool
     */
    function getDelegationShares(address _indexer, address _delegator)
        public
        view
        returns (uint256)
    {
        return delegation[_indexer].delegatorShares[_delegator];
    }

    /**
     * @dev Get the amount of tokens a delegator has in a delegation pool
     * @param _indexer Address of the indexer
     * @param _delegator Address of the delegator
     * @return Tokens owned by delegator in a delegation pool
     */
    function getDelegationTokens(address _indexer, address _delegator)
        public
        view
        returns (uint256)
    {
        // Get the delegation pool of the indexer
        DelegationPool storage pool = delegation[_indexer];
        if (pool.shares == 0) {
            return 0;
        }
        uint256 _shares = getDelegationShares(_indexer, _delegator);
        return _shares.mul(pool.tokens).div(pool.shares);
    }

    /**
     * @dev Get the total amount of tokens staked by the indexer
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address _indexer) public view returns (uint256) {
        return stakes[_indexer].tokensStaked;
    }

    /**
     * @dev Get the total amount of tokens available to use in allocations.
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerCapacity(address _indexer) public view returns (uint256) {
        Stakes.Indexer memory indexerStake = stakes[_indexer];
        DelegationPool memory pool = delegation[_indexer];

        uint256 tokensDelegatedMax = indexerStake.tokensStaked.mul(delegationCapacity);
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
     * @dev Get an outstanding unclaimed settlement
     * @param _epoch Epoch when the settlement ocurred
     * @param _indexer Address of the indexer
     * @param _subgraphDeploymentID ID of the SubgraphDeployment settled
     * @return Settlement data
     */
    function getSettlement(
        uint256 _epoch,
        address _indexer,
        bytes32 _subgraphDeploymentID
    ) public view returns (Rebates.Settlement memory) {
        return rebates[_epoch].settlements[_indexer][_subgraphDeploymentID];
    }

    /**
     * @dev Slash the indexer stake
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
    ) external onlySlasher {
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        require(_tokens > 0, "Slashing: cannot slash zero tokens");
        require(_tokens >= _reward, "Slashing: reward cannot be higher than slashed amount");
        require(indexerStake.hasTokens(), "Slashing: indexer has no stakes");
        require(
            _tokens <= indexerStake.tokensStaked,
            "Slashing: cannot slash more than staked amount"
        );
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
     * @dev Deposit tokens on the indexer stake
     * @param _tokens Amount of tokens to stake
     */
    function stake(uint256 _tokens) external {
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
     * @dev Unstake tokens from the indexer stake, lock them until thawing period expires
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external {
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
     * @dev Delegate tokens to an indexer.
     * @param _indexer Address of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     */
    function delegate(address _indexer, uint256 _tokens) external {
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
    function undelegate(address _indexer, uint256 _shares) external {
        address delegator = msg.sender;

        // Update state
        uint256 tokens = _undelegate(delegator, _indexer, _shares);

        // Return tokens to delegator
        require(token.transfer(delegator, tokens), "Delegation: error sending tokens");
    }

    /**
     * @dev Switch delegation to other indexer.
     * @param _srcIndexer Address of the indexer source of redelegated funds
     * @param _dstIndexer Address of the indexer target of redelegated funds
     * @param _shares Amount of shares to redelegate
     */
    function redelegate(
        address _srcIndexer,
        address _dstIndexer,
        uint256 _shares
    ) external {
        address delegator = msg.sender;

        // Can only redelegate to a different indexer
        require(_srcIndexer != _dstIndexer, "Delegation: cannot redelegate to same indexer");

        _delegate(delegator, _dstIndexer, _undelegate(delegator, _srcIndexer, _shares));
    }

    /**
     * @dev Allocate available tokens to a SubgraphDeployment.
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
    ) external {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        // Only allocations with a non-zero token amount are allowed
        require(_tokens > 0, "Allocation: cannot allocate zero tokens");

        // Needs to have tokens in our stake to be able to allocate
        require(indexerStake.hasTokens(), "Allocation: indexer has no stakes");

        // Needs to have free capacity not used for other purposes to allocate
        require(
            getIndexerCapacity(indexer) >= _tokens,
            "Allocation: not enough tokens available to allocate"
        );

        // Can only allocate tokens to a SubgraphDeployment if not currently allocated
        require(
            indexerStake.hasAllocation(_subgraphDeploymentID) == false,
            "Allocation: cannot allocate if already allocated"
        );

        // Channel public key must be in uncompressed format
        require(
            uint8(_channelPubKey[0]) == 4 && _channelPubKey.length == 65,
            "Allocation: invalid channel public key"
        );

        // A channel public key is derived by the indexer when creating the offchain payment channel.
        // Get the Ethereum address from the public key and use as channel identifier.
        // The channel identifier is the address of the indexer signing party of a multisig that
        // will hold the funds received when the channel is settled.
        address channelID = address(uint256(keccak256(bytes(_channelPubKey[1:])))); // solium-disable-line

        // Cannot reuse a channelID that has already been used in an allocation
        require(isChannel(channelID) == false, "Allocation: channel ID already used");

        // TODO: track counter of multiple allocations allowed for the same (indexer,subgraphDeployment)

        // Create allocation linked to the channel identifier
        allocations[channelID] = Allocation(
            indexer,
            _subgraphDeploymentID,
            _tokens,
            epochManager.currentEpoch(), // createdAtEpoch
            0, // settledAtEpoch
            0, // start we zero collected fees
            0 // effective allocation
        );

        // Mark allocated tokens as used
        indexerStake.allocate(_tokens);

        // The channel proxy address is the contract that will send tokens to be settled to
        // this contract. Create a link to the channelID to properly assign funds settled.
        channelsProxy[_channelProxy] = channelID;

        emit AllocationCreated(
            indexer,
            _subgraphDeploymentID,
            allocations[channelID].createdAtEpoch,
            allocations[channelID].tokens,
            channelID,
            _channelPubKey,
            _price
        );
    }

    function unallocate(address _channelID) external {
        address indexer = msg.sender;

        // Get allocation related to the channel identifier
        Allocation storage alloc = allocations[_channelID];

        // Allocation must exist
        require(isChannel(_channelID), "Allocation: channelID not used in any allocation");

        // Verify that the allocation owner is unallocating
        // TODO: also allow delegator to force it after a period
        require(alloc.indexer == indexer, "Allocation: only allocation owner allowed");

        // Must be an active allocation
        require(alloc.settledAtEpoch == 0, "Allocation: must be active");

        // Validate that an allocation cannot be settled before one epoch
        (uint256 epochs, uint256 currentEpoch) = epochManager.epochsSince(alloc.createdAtEpoch);
        require(epochs > 0, "Allocation: must pass at least one epoch");

        // Settle the allocation and start counting a period to finalize any other
        // withdrawal from the related channel.
        alloc.settledAtEpoch = currentEpoch;
        alloc.effectiveAllocation = getEffectiveAllocation(alloc.tokens, epochs);

        // TODO: find a rebate pool for the epoch and accumulate stuff there
        // TODO: review if we can replace Settlement with Allocation
        // TODO: can we unallocate two Allocations on the same epoch - rebate?
        Rebates.Pool storage rebatePool = rebates[currentEpoch];
        rebatePool.fees = rebatePool.fees.add(alloc.collectedFees);
        rebatePool.allocation = rebatePool.allocation.add(alloc.effectiveAllocation);
        rebatePool.settlementsCount += 1;

        // Free allocated tokens from use
        indexerStake.unallocate(_tokens);

        // TODO: emit event
    }

    /**
     * @dev Collected query fees from a channel.
     * Funds received are only accepted from a channel multisig proxy contract.
     * @param _tokens Amount of tokens to settle
     */
    function settle(uint256 _tokens) external {
        // The contract caller must only be a channel proxy registered during allocation
        // Get the channelID related to the caller channel proxy
        address channelID = channelsProxy[msg.sender];

        // Channel validation
        require(channelID != address(0), "Settle: caller not allowed to settle");

        // The channelID must exist and used in an allocation
        require(isChannel(channelID), "Settle: does not exist");

        // Transfer tokens to collect from multisig to this contract
        require(
            token.transferFrom(msg.sender, address(this), _tokens),
            "Settle: cannot transfer tokens to settle"
        );

        _settle(channelID, msg.sender, _tokens);
    }

    /**
     * @dev Withdraw tokens once the thawing period has passed
     */
    function withdraw() external {
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
     * @dev Claim tokens from the rebate pool
     * @param _epoch Epoch of the rebate pool we are claiming tokens from
     * @param _subgraphDeploymentID SubgraphDeployment we are claiming tokens from
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claim(
        uint256 _epoch,
        bytes32 _subgraphDeploymentID,
        bool _restake
    ) external {
        address indexer = msg.sender;
        Rebates.Pool storage pool = rebates[_epoch];
        Rebates.Settlement storage settlement = pool.settlements[indexer][_subgraphDeploymentID];

        (uint256 epochsSinceSettlement, uint256 currentEpoch) = epochManager.epochsSince(_epoch);

        require(
            epochsSinceSettlement >= channelDisputeEpochs,
            "Rebate: need to wait channel dispute period"
        );

        require(settlement.allocation > 0, "Rebate: settlement does not exist");

        // Process rebate
        uint256 tokensToClaim = pool.redeem(indexer, _subgraphDeploymentID);

        // When all settlements processed then prune rebate pool
        if (pool.settlementsCount == 0) {
            delete rebates[_epoch];
        }

        // Calculate delegation fees and add them to the delegation pool
        uint256 delegationFees = _collectDelegationFees(indexer, tokensToClaim);
        tokensToClaim = tokensToClaim.sub(delegationFees);

        // When there are tokens to claim from the rebate pool, transfer or restake
        if (tokensToClaim > 0) {
            // Assign claimed tokens
            if (_restake) {
                // Restake to place fees into the indexer stake
                _stake(indexer, tokensToClaim);
            } else {
                // Transfer funds back to the indexer
                require(token.transfer(indexer, tokensToClaim), "Rebate: cannot transfer tokens");
            }
        }

        emit RebateClaimed(
            indexer,
            _subgraphDeploymentID,
            currentEpoch,
            _epoch,
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
     * @dev Settle a channel after receiving collected query fees from it.
     * @param _channelID ChannelID address of the indexer in the channel
     * @param _from Multisig channel address that triggered settlement
     * @param _tokens Amount of tokens to settle
     */
    function _settle(
        address _channelID,
        address _from,
        uint256 _tokens
    ) private {
        // Get allocation related to the channel identifier
        Allocation storage alloc = allocations[_channelID];

        // TODO: validate the the allocation can still be settled

        // Calculate curation fees only if the subgraph deployment is curated
        uint256 curationFees = _collectCurationFees(alloc.subgraphDeploymentID, _tokens);

        // Hold tokens received in the allocation
        uint256 rebateFees = _tokens.sub(curationFees);
        alloc.collectedFees = alloc.collectedFees.add(rebateFees);

        // Send curation fees to the curator SubgraphDeployment reserve
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            require(token.approve(address(curation), curationFees));
            curation.collect(alloc.subgraphDeploymentID, curationFees);
        }

        emit AllocationSettled(
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
        DelegationPool storage pool = delegation[_indexer];

        // Calculate shares to issue
        uint256 shares = (pool.tokens == 0) ? _tokens : _tokens.mul(pool.shares).div(pool.tokens);

        // Update the delegation pool
        pool.tokens = pool.tokens.add(_tokens);
        pool.shares = pool.shares.add(shares);
        pool.delegatorShares[_delegator] = pool.delegatorShares[_delegator].add(shares);

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
        DelegationPool storage pool = delegation[_indexer];

        // Delegator need to have enough shares in the pool to undelegate
        require(
            pool.delegatorShares[_delegator] >= _shares,
            "Delegation: delegator does not have enough shares"
        );

        // Calculate tokens to get in exchange for the shares
        uint256 tokens = _shares.mul(pool.tokens).div(pool.shares);

        // Update the delegation pool
        pool.tokens = pool.tokens.sub(tokens);
        pool.shares = pool.shares.sub(_shares);
        pool.delegatorShares[_delegator] = pool.delegatorShares[_delegator].sub(_shares);

        emit StakeUndelegated(_indexer, _delegator, tokens, _shares);

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
        DelegationPool storage pool = delegation[_indexer];
        if (pool.tokens > 0 && pool.queryFeeCut < MAX_PPM) {
            uint256 indexerCut = pool.queryFeeCut.mul(_tokens).div(MAX_PPM);
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
        if (isCurationEnabled() && curation.isCurated(_subgraphDeploymentID)) {
            return curationPercentage.mul(_tokens).div(MAX_PPM);
        }
        return 0;
    }

    /**
     * @dev Get whether curation rewards are active or not
     * @return true if curation fees are enabled
     */
    function isCurationEnabled() private view returns (bool) {
        return curationPercentage > 0 && address(curation) != address(0);
    }

    /**
     * @dev Get the effective stake allocation considering epochs from allocation to settlement.
     * @param _tokens Amount of tokens allocated
     * @param _numEpochs Number of epochs that passed from allocation to settlement
     * @return Effective allocated tokens accross epochs
     */
    function getEffectiveAllocation(uint256 _tokens, uint256 _numEpochs)
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
}
