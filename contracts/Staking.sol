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

    // -- Allocation and Channel --

    struct Channel {
        address indexer;
        bytes32 subgraphDeploymentID;
    }

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public curationPercentage;

    // Need to pass this period to claim fees in rebate pool
    uint256 public channelDisputeEpochs;

    // Maximum allocation time
    uint256 public maxAllocationEpochs;

    // Channels : channelID => Channel
    mapping(address => Channel) public channels;

    // Channels Proxy : Channel Multisig Proxy => channelID
    mapping(address => address) public channelsProxy;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // -- Slashing --

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // -- Delegation --

    struct DelegationParameters {
        uint256 indexingRewardCut;
        uint256 queryFeeCut;
        uint256 cooldownBlocks;
        uint256 createdAtBlock;
    }

    // Set the delegation capacity multiplier, an indexer delegation capacity will be:
    // max(tokensStaked+tokensDelegated, totalStaked*delegationCapacity)
    uint256 delegationCapacity;

    // Time in blocks an indexer needs to wait to change delegation parameters
    uint256 delegationParametersCooldown;

    // Delegation parameters
    mapping(address => DelegationParameters) public delegationParameters;

    // -- Related contracts --

    GraphToken public token;
    EpochManager public epochManager;
    Curation public curation;

    // -- Events --

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
     * @dev Emitted when `delegator` delegated `tokens` to the `indexer`.
     */
    event StakeDelegated(address indexed indexer, address indexed delegator, uint256 tokens);

    /**
     * @dev Emitted when `delegator` undelegated `tokens` from `indexer`.
     */
    event StakeUndelegated(address indexed indexer, address indexed delegator, uint256 tokens);

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
        uint256 rebateFees,
        uint256 effectiveAllocation
    );

    /**
     * @dev Emitted when `indexer` claimed a rebate on `subgraphDeploymentID` during `epoch`
     * related to the `forEpoch` rebate pool.
     * The rebate is for `tokens` amount and an outstanding `settlements` count are
     * left for claim in the rebate pool.
     */
    event RebateClaimed(
        address indexed indexer,
        bytes32 indexed subgraphDeploymentID,
        uint256 epoch,
        uint256 forEpoch,
        uint256 tokens,
        uint256 settlements
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

        // Cooldown period set by indexer cannot be below protocol global setting
        require(
            _cooldownBlocks >= delegationParametersCooldown,
            "Delegation: cooldown cannot be below minimum"
        );

        // Verify the cooldown period passed
        DelegationParameters memory params = delegationParameters[indexer];
        require(
            params.createdAtBlock == 0 ||
                params.createdAtBlock.add(params.cooldownBlocks) <= block.number,
            "Delegation: must expire cooldown period to update parameters"
        );

        // Update delegation params
        delegationParameters[indexer] = DelegationParameters(
            _indexingRewardCut,
            _queryFeeCut,
            _cooldownBlocks,
            block.number
        );

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
     * @dev Return if channelID (address) is already used
     * @param _channelID Address used as signer for indexer in channel
     * @return True if channelID already used
     */
    function isChannel(address _channelID) public view returns (bool) {
        return channels[_channelID].indexer != address(0);
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
     * @dev Get the total amount of tokens staked by the indexer
     * @param _indexer Address of the indexer
     * @return Amount of tokens staked by the indexer
     */
    function getIndexerStakedTokens(address _indexer) public view returns (uint256) {
        return stakes[_indexer].tokensStaked;
    }

    /**
     * @dev Get an allocation of tokens to a SubgraphDeployment
     * @param _indexer Address of the indexer
     * @param _subgraphDeploymentID ID of the SubgraphDeployment to query
     * @return Allocation data
     */
    function getAllocation(address _indexer, bytes32 _subgraphDeploymentID)
        public
        view
        returns (Stakes.Allocation memory)
    {
        return stakes[_indexer].allocations[_subgraphDeploymentID];
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
        require(_beneficiary != address(0), "Slashing: beneficiary must not be an empty address");
        require(
            _tokens <= indexerStake.tokensSlashable(),
            "Slashing: cannot slash more than staked amount"
        );

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
            "Staking: Cannot transfer tokens to stake"
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
     * @dev Delegate tokens to an indexer
     * @param _indexer Addres of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     */
    function delegate(address _indexer, uint256 _tokens) external {
        address delegator = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[_indexer];

        require(_tokens > 0, "Delegation: cannot delegate zero tokens");

        indexerStake.tokensDelegated = indexerStake.tokensDelegated.add(_tokens);

        emit StakeDelegated(_indexer, delegator, _tokens);
    }

    /**
     * @dev Undelegate tokens from an indexer
     * @param _indexer Addres of the indexer to delegate tokens to
     * @param _tokens Amount of tokens to delegate
     */
    function undelegate(address _indexer, uint256 _tokens) external {
        address delegator = msg.sender;

        require(_tokens > 0, "Delegation: cannot undelegate zero tokens");

        emit StakeUndelegated(_indexer, delegator, _tokens);
    }

    /**
     * @dev Allocate available tokens to a SubgraphDeployment
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

        // Only allocations with a token amount are allowed
        require(_tokens > 0, "Allocation: cannot allocate zero tokens");
        // Need to have tokens in our stake to be able to allocate
        require(indexerStake.hasTokens(), "Allocation: indexer has no stakes");
        // Need to have free tokens not used for other purposes to allocate
        require(
            indexerStake.tokensAvailable() >= _tokens,
            "Allocation: not enough tokens available to allocate"
        );
        // Can only allocate tokens to a SubgraphDeployment if not currently allocated
        require(
            indexerStake.hasAllocation(_subgraphDeploymentID) == false,
            "Allocation: cannot allocate if already allocated"
        );
        // Cannot reuse a channelID that has been used in the past
        address channelID = publicKeyToAddress(bytes(_channelPubKey[1:])); // solium-disable-line
        require(isChannel(channelID) == false, "Allocation: channel ID already in use");

        // Allocate and setup channel
        Stakes.Allocation storage alloc = indexerStake.allocateTokens(
            _subgraphDeploymentID,
            _tokens
        );
        alloc.channelID = channelID;
        alloc.createdAtEpoch = epochManager.currentEpoch();
        channels[channelID] = Channel(indexer, _subgraphDeploymentID);
        channelsProxy[_channelProxy] = channelID;

        emit AllocationCreated(
            indexer,
            _subgraphDeploymentID,
            alloc.createdAtEpoch,
            alloc.tokens,
            channelID,
            _channelPubKey,
            _price
        );
    }

    /**
     * @dev Settle a channel after receiving collected query fees from it
     * Funds are received from a channel multisig proxy contract
     * @param _tokens Amount of tokens to settle
     */
    function settle(uint256 _tokens) external {
        // Get the channelID the caller is related
        address channelID = channelsProxy[msg.sender];

        // Receive funds from the channel multisig
        // We use channelID to find the indexer owner of the channel
        require(isChannel(channelID), "Channel: does not exist");

        delete channelsProxy[msg.sender]; // Remove to avoid re-entrancy

        // Transfer tokens to settle from multisig to this contract
        require(
            token.transferFrom(msg.sender, address(this), _tokens),
            "Channel: Cannot transfer tokens to settle"
        );
        _settle(channelID, msg.sender, _tokens);
    }

    /**
     * @dev Withdraw tokens once the thawing period has passed
     */
    function withdraw() external {
        address indexer = msg.sender;
        Stakes.Indexer storage indexerStake = stakes[indexer];

        uint256 tokensToWithdraw = indexerStake.withdrawTokens();
        require(tokensToWithdraw > 0, "Staking: no tokens available to withdraw");

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
            pool.settlementsCount
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
     * @dev Settle a channel after receiving collected query fees from it
     * @param _channelID ChannelID - address of the indexer in the channel
     * @param _from Multisig channel address that triggered settlement
     * @param _tokens Amount of tokens to settle
     */
    function _settle(
        address _channelID,
        address _from,
        uint256 _tokens
    ) private {
        address indexer = channels[_channelID].indexer;
        bytes32 subgraphDeploymentID = channels[_channelID].subgraphDeploymentID;
        Stakes.Allocation storage alloc = stakes[indexer].allocations[subgraphDeploymentID];

        require(_channelID != address(0), "Channel: ChannelID cannot be empty address");
        require(
            alloc.channelID == _channelID,
            "Channel: The allocation has no channel, or the channel was already settled"
        );

        // Time conditions
        (uint256 epochs, uint256 currentEpoch) = epochManager.epochsSince(alloc.createdAtEpoch);
        require(epochs > 0, "Channel: Can only settle after one epoch passed");

        // Calculate curation fees
        uint256 curationFees = (isCurationEnabled() && curation.isCurated(subgraphDeploymentID))
            ? curationPercentage.mul(_tokens).div(MAX_PPM)
            : 0;

        // Set apart fees into a rebate pool
        uint256 rebateFees = _tokens.sub(curationFees);
        uint256 effectiveAllocation = alloc.getTokensEffectiveAllocation(
            epochs,
            maxAllocationEpochs
        );
        rebates[currentEpoch].add(indexer, subgraphDeploymentID, rebateFees, effectiveAllocation);

        // Close channel
        // NOTE: Channels used are never deleted from state tracked in `channels` var
        stakes[indexer].unallocateTokens(subgraphDeploymentID, alloc.tokens);
        alloc.channelID = address(0);
        alloc.createdAtEpoch = 0;
        // TODO: send multisig one-shot invalidation

        // Send curation fees to the curator SubgraphDeployment reserve
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            require(token.approve(address(curation), curationFees));
            curation.collect(subgraphDeploymentID, curationFees);
        }

        emit AllocationSettled(
            indexer,
            subgraphDeploymentID,
            currentEpoch,
            _tokens,
            _channelID,
            _from,
            curationFees,
            rebateFees,
            effectiveAllocation
        );
    }

    /**
     * @dev Get whether curation rewards are active or not
     * @return true if curation fees are enabled
     */
    function isCurationEnabled() private view returns (bool) {
        return curationPercentage > 0 && address(curation) != address(0);
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
     * @dev Convert an uncompressed public key to an Ethereum address
     * @param _publicKey Public key in uncompressed format without the 1 byte prefix
     * @return An Ethereum address corresponding to the public key
     */
    function publicKeyToAddress(bytes memory _publicKey) private pure returns (address) {
        uint256 mask = 2**(8 * 21) - 1;
        uint256 value = uint256(keccak256(_publicKey));
        return address(value & mask);
    }
}
