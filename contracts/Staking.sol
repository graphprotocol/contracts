pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Staking contract
 */

import "./Curation.sol";
import "./EpochManager.sol";
import "./Governed.sol";
import "./GraphToken.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";
import "./bytes/BytesLib.sol";


contract Staking is Governed {
    using BytesLib for bytes;
    using SafeMath for uint256;
    using Stakes for Stakes.Indexer;
    using Stakes for Stakes.Allocation;
    using Rebates for Rebates.Pool;

    // -- Stakes --

    struct Channel {
        address indexer;
        bytes32 subgraphID;
    }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // -- State --

    // Percentage of fees going to curators
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public curationPercentage;

    // Need to pass this period to claim fees in rebate pool
    uint256 public channelDisputeEpochs;

    // Maximum allocation time
    uint256 public maxAllocationEpochs;

    // Time in blocks to unstake
    uint256 public thawingPeriod; // in blocks

    // Indexer stake tracking : indexer => Stake
    mapping(address => Stakes.Indexer) public stakes;

    // Channels : channelID => Channel
    mapping(address => Channel) public channels;

    // Rebate pools : epoch => Pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // Related contracts
    GraphToken public token;
    EpochManager public epochManager;
    Curation public curation;

    // -- Events --

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
     * @dev Emitted when `indexer` withdrew `tokens` staked amount
     */
    event StakeWithdrawn(address indexed indexer, uint256 tokens);

    /**
     * @dev Emitted when `indexer` allocated `tokens` amount to `subgraphID`
     * during `epoch`.
     * `channelID` is the address of the indexer in the channel multisig.
     * `channelPubKey` is the public key used for routing payments to the indexer channel.
     */
    event AllocationCreated(
        address indexed indexer,
        bytes32 indexed subgraphID,
        uint256 epoch,
        uint256 tokens,
        address channelID,
        bytes channelPubKey
    );

    /**
     * @dev Emitted when `indexer` settled an allocation of `tokens` amount to `subgraphID`
     * during `epoch` using `channelID` as channel.
     *
     * NOTE: `from` tracks the multisig contract from where it was settled.
     */
    event AllocationSettled(
        address indexed indexer,
        bytes32 indexed subgraphID,
        uint256 epoch,
        uint256 tokens,
        address channelID,
        address from,
        uint256 curationFees,
        uint256 rebateFees
    );

    /**
     * @dev Emitted when `indexer` claimed a rebate on `subgraphID` during `epoch`
     * related to the `forEpoch` rebate pool.
     * The rebate is for `tokens` amount and an outstanding `settlements` count are
     * left for claim in the rebate pool.
     */
    event RebateClaimed(
        address indexed indexer,
        bytes32 indexed subgraphID,
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
     * @param _curation Address of the Curation contract
     */
    constructor(
        address _governor,
        address _token,
        address _epochManager,
        address _curation
    ) public Governed(_governor) {
        token = GraphToken(_token);
        epochManager = EpochManager(_epochManager);
        curation = Curation(_curation);
    }

    /**
     * @dev Set the curation contract where to send curation fees
     * @param _curation Address of the curation contract
     */
    function setCuration(Curation _curation) external onlyGovernor {
        curation = _curation;
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
    function getIndexerStakeTokens(address _indexer) public view returns (uint256) {
        return stakes[_indexer].tokensIndexer;
    }

    /**
     * @dev Get an allocation of tokens to a subgraph
     * @param _indexer Address of the indexer
     * @param _subgraphID ID of the subgraph to query
     * @return Allocation data
     */
    function getAllocation(address _indexer, bytes32 _subgraphID)
        public
        view
        returns (Stakes.Allocation memory)
    {
        return stakes[_indexer].allocations[_subgraphID];
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

        require(indexerStake.hasTokens(), "Slashing: indexer has no stakes");
        require(_beneficiary != address(0), "Slashing: beneficiary must not be an empty address");
        require(_tokens >= _reward, "Slashing: reward cannot be higher than slashed amount");
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
     * @dev Allocate available tokens to a subgraph
     * @param _subgraphID ID of the subgraph where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelPubKey The public key used by the indexer to setup the off-chain channel
     */
    function allocate(
        bytes32 _subgraphID,
        uint256 _tokens,
        bytes calldata _channelPubKey
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
        // Can only allocate tokens to a subgraph if not currently allocated
        require(
            indexerStake.hasAllocation(_subgraphID) == false,
            "Allocation: cannot allocate if already allocated"
        );
        // Cannot reuse a channelID that has been used in the past
        address channelID = publicKeyToAddress(bytes(_channelPubKey[1:])); // solium-disable-line
        require(isChannel(channelID) == false, "Allocation: channel ID already in use");

        // Allocate and setup channel
        Stakes.Allocation storage alloc = indexerStake.allocateTokens(_subgraphID, _tokens);
        alloc.channelID = channelID;
        alloc.createdAtEpoch = epochManager.currentEpoch();
        channels[channelID] = Channel(indexer, _subgraphID);

        emit AllocationCreated(
            indexer,
            _subgraphID,
            alloc.createdAtEpoch,
            alloc.tokens,
            channelID,
            _channelPubKey
        );
    }

    /**
     * @dev Settle a channel after receiving collected query fees from it
     * @param _channelID Address of the indexer in the channel
     * @param _tokens Amount of tokens to settle
     */
    function settle(address _channelID, uint256 _tokens) external {
        address channelMultisig = msg.sender;

        // Receive funds from the channel multisig
        // We use channelID to find the indexer owner of the channel
        require(isChannel(_channelID), "Channel: does not exist");

        // Transfer tokens to settle from multisig to this contract
        require(
            token.transferFrom(channelMultisig, address(this), _tokens),
            "Channel: Cannot transfer tokens to settle"
        );
        _settle(_channelID, channelMultisig, _tokens);
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
     * @param _subgraphID Subgraph we are claiming tokens from
     * @param _restake True if restake fees instead of transfer to indexer
     */
    function claim(
        uint256 _epoch,
        bytes32 _subgraphID,
        bool _restake
    ) external {
        address indexer = msg.sender;
        Rebates.Pool storage pool = rebates[_epoch];
        Rebates.Settlement storage settlement = pool.settlements[indexer][_subgraphID];

        (uint256 epochsSinceSettlement, uint256 currentEpoch) = epochManager.epochsSince(_epoch);

        require(
            epochsSinceSettlement >= channelDisputeEpochs,
            "Rebate: need to wait channel dispute period"
        );
        require(settlement.allocation > 0, "Rebate: settlement does not exist");

        // Process rebate
        uint256 tokensToClaim = pool.redeem(indexer, _subgraphID);
        require(tokensToClaim > 0, "Rebate: no tokens available to claim");

        // All settlements processed then prune rebate pool
        if (pool.settlementsCount == 0) {
            delete rebates[_epoch];
        }

        // Assign claimed tokens
        if (_restake) {
            // Restake to place fees into the indexer stake
            _stake(indexer, tokensToClaim);
        } else {
            // Transfer funds back to the indexer
            require(token.transfer(indexer, tokensToClaim), "Rebate: cannot transfer tokens");
        }

        emit RebateClaimed(
            indexer,
            _subgraphID,
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
        bytes32 subgraphID = channels[_channelID].subgraphID;
        Stakes.Indexer storage indexerStake = stakes[indexer];
        Stakes.Allocation storage alloc = indexerStake.allocations[subgraphID];

        require(alloc.hasChannel(), "Channel: Must be active for settlement");

        // Time conditions
        (uint256 epochs, uint256 currentEpoch) = epochManager.epochsSince(alloc.createdAtEpoch);
        require(epochs > 0, "Channel: Can only settle after one epoch passed");

        // Calculate curation fees
        uint256 curationFees = (isCurationEnabled() && curation.isSubgraphCurated(subgraphID))
            ? curationPercentage.mul(_tokens).div(MAX_PPM)
            : 0;

        // Set apart fees into a rebate pool
        uint256 rebateFees = _tokens.sub(curationFees);
        rebates[currentEpoch].add(
            indexer,
            subgraphID,
            rebateFees,
            alloc.getTokensEffectiveAllocation(epochs, maxAllocationEpochs)
        );

        // Close channel
        // NOTE: Channels used are never deleted from state tracked in `channels` var
        indexerStake.unallocateTokens(subgraphID, alloc.tokens);
        alloc.channelID = address(0);
        alloc.createdAtEpoch = 0;
        // TODO: send multisig one-shot invalidation

        // Send curation fees to the curator subgraph reserve
        if (curationFees > 0) {
            // TODO: the approve call can be optimized by approving the curation contract to fetch
            // funds from the Staking contract for infinity funds just once for a security tradeoff
            require(token.approve(address(curation), curationFees));
            curation.collect(subgraphID, curationFees);
        }

        emit AllocationSettled(
            indexer,
            subgraphID,
            currentEpoch,
            _tokens,
            _channelID,
            _from,
            rebateFees,
            curationFees
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
