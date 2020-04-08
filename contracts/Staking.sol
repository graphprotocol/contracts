pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Staking contract
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./EpochManager.sol";
import "./bytes/BytesLib.sol";


library Stakes {
    enum ChannelStatus { Closed, Active }

    struct Allocation {
        uint256 tokens; // Tokens allocated to a subgraph
        uint256 createdAtEpoch; // Epoch when it was created
        bytes channelID; // IndexNode xpub used in off-chain channel
        ChannelStatus status; // Current status
    }

    struct IndexNode {
        uint256 tokens; // Tokens on this stake (IndexNode + Delegators)
        uint256 tokensAllocated; // Tokens used in subgraph allocations
        uint256 tokensAvailable; // Tokens available for the IndexNode to allocate
        mapping(bytes32 => Allocation) allocations; // Subgraph stake tracking
    }
}


contract Staking is Governed {
    using BytesLib for bytes;
    using SafeMath for uint256;
    using Stakes for Stakes.IndexNode;

    // -- Stakes --

    enum TokenReceiptAction { Staking, Settlement }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // -- State --

    uint256 public maxSettlementDuration; // in epochs

    // Percentage of index node stake to slash on disputes
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercentage;

    // Time in blocks to unstake
    uint256 public thawingPeriod;

    // IndexNode stake tracking
    mapping(address => Stakes.IndexNode) public stakes;

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // Payment channels
    mapping(bytes => bool) public channels;

    // Related contracts
    GraphToken public token;
    EpochManager public epochManager;

    // -- Events --

    event StakeUpdate(address indexed indexNode, uint256 tokens);
    event AllocationUpdate(address indexed indexNode, bytes32 indexed subgraphID, uint256 tokens);
    event SlasherUpdate(address indexed caller, address indexed slasher, bool enabled);

    modifier onlySlasher {
        require(slashers[msg.sender] == true, "Caller is not a Slasher");
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor Address of the multisig contract as Governor of this contract
     * @param _token Address of the Graph Protocol token
     * @param _epochManager Address of the EpochManager contract
     * @param _maxSettlementDuration Max settlement duration
     * @param _slashingPercentage Percentage of index node stake slashed after a dispute
     */
    constructor(
        address _governor,
        address _token,
        address _epochManager,
        uint256 _maxSettlementDuration,
        uint256 _slashingPercentage
    ) public Governed(_governor) {
        token = GraphToken(_token);
        epochManager = EpochManager(_epochManager);
        maxSettlementDuration = _maxSettlementDuration;
        slashingPercentage = _slashingPercentage;
    }

    /**
     * @dev Set the max settlement time allowed for index nodes
     * @param _maxSettlementDuration Settlement duration limit in epochs
     */
    function setMaxSettlementDuration(uint256 _maxSettlementDuration) external onlyGovernor {
        maxSettlementDuration = _maxSettlementDuration;
    }

    /**
     * @dev Set an address as allowed slasher
     * @param _slasher Address of the party allowed to slash index nodes
     * @param _allowed True if slasher is allowed
     */
    function setSlasher(address _slasher, bool _allowed) external onlyGovernor {
        slashers[_slasher] = _allowed;
        emit SlasherUpdate(msg.sender, _slasher, _allowed);
    }

    /**
     * @dev Set the percentage used for slashing index nodes
     * @param _percentage Percentage used for slashing
     */
    function setSlashingPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Slashing percentage must be below or equal to MAX_PPM");

        slashingPercentage = _percentage;
    }

    /**
     * @dev Set the thawing period for unstaking
     * @param _thawingPeriod Time need to pass in blocks to withdraw stake
     */
    function setThawingPeriod(uint256 _thawingPeriod) external onlyGovernor {
        thawingPeriod = _thawingPeriod;
    }

    /**
     * @dev Get if an index node has any stake
     * @param _indexNode Address of the index node
     * @return True if index node has staked tokens
     */
    function hasStake(address _indexNode) public view returns (bool) {
        return getStakeTokens(_indexNode) > 0;
    }

    /**
     * @dev Get the total amount of tokens staked by the index node
     * @param _indexNode Address of the index node
     * @return Amount of tokens staked by the index node
     */
    function getStakeTokens(address _indexNode) public view returns (uint256) {
        return stakes[_indexNode].tokens;
    }

    /**
     * @dev Get the amount of tokens to slash for an index node based on its total stake
     * @param _indexNode Address of the index node
     * @return Amount of tokens to slash
     */
    function getSlashingAmount(address _indexNode) public view returns (uint256) {
        uint256 tokens = getStakeTokens(_indexNode);
        return slashingPercentage.mul(tokens).div(MAX_PPM); // slashingPercentage is in PPM
    }

    /**
     * @dev Get an allocation of tokens to a subgraph
     * @param _indexNode Address of the index node
     * @param _subgraphID ID of the subgraph to query
     * @return Allocation data
     */
    function getAllocation(address _indexNode, bytes32 _subgraphID)
        public
        view
        returns (Stakes.Allocation memory)
    {
        return stakes[_indexNode].allocations[_subgraphID];
    }

    /**
     * @dev Slash the index node stake
     * @param _indexNode Address of index node to slash
     * @param _reward Amount of reward to send to a beneficiary
     * @param _beneficiary Address of a beneficiary to receive a reward for the slashing
     */
    function slash(address _indexNode, uint256 _reward, address _beneficiary) external onlySlasher {
        // Beneficiary conditions
        require(_beneficiary != address(0), "Slash: beneficiary must not be an empty address");

        // Get stake to be slashed
        uint256 stakeTokens = getStakeTokens(_indexNode);

        // Index node need to have stakes
        require(stakeTokens > 0, "Slash: index node has no stakes");

        // Slash stake
        uint256 tokensToSlash = getSlashingAmount(_indexNode);
        stakes[_indexNode].tokens = stakeTokens.sub(tokensToSlash);
        // TODO: how do we updated the available tokens?

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        uint256 tokensToBurn = tokensToSlash.sub(
            _reward,
            "Slash: reward cannot be higher than slashed amount"
        );
        if (tokensToBurn > 0) {
            token.burn(tokensToBurn);
        }

        // Give the beneficiary a reward for slashing
        if (_reward > 0) {
            require(token.transfer(_beneficiary, _reward), "Slash: error sending dispute reward");
        }

        emit StakeUpdate(_indexNode, getStakeTokens(_indexNode));
    }

    /**
     * @dev Accept tokens and handle staking registration functions
     * @param _from Token holder's address
     * @param _value Amount of Graph Tokens
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token), "Caller is not the GRT token contract");

        // Parse token received payload
        TokenReceiptAction option = TokenReceiptAction(_data.slice(0, 1).toUint8(0));

        // Action according to payload
        if (option == TokenReceiptAction.Staking) {
            _stake(_from, _value);
        } else {
            revert("Token received option must be 0 or 1");
        }
        return true;
    }

    /**
     * @dev Allocate available tokens to a subgraph
     * @param _subgraphID ID of the subgraph where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelID xpub used to identify off-chain payment channels
     */
    function allocate(bytes32 _subgraphID, uint256 _tokens, bytes calldata _channelID) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];
        Stakes.Allocation storage allocation = stake.allocations[_subgraphID];

        require(stake.tokensAvailable >= _tokens, "Allocate: not enough available tokens");

        _setupChannel(allocation, _channelID);
        allocation.tokens = allocation.tokens.add(_tokens);
        stake.tokensAvailable = stake.tokensAvailable.sub(_tokens);

        emit AllocationUpdate(indexNode, _subgraphID, allocation.tokens);
    }

    /**
     * @dev Unallocate tokens from a subgraph
     * @param _subgraphID ID of the subgraph where tokens are allocated
     */
    function unallocate(bytes32 _subgraphID) external {
        address indexNode = msg.sender;

        // TODO
        // check subgraph allocation exist
        // check balances are enough
        // channel must be closed
        // move balances to the main stack
    }

    /**
     * @dev Withdraw tokens from the index node stake
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(hasStake(indexNode), "Stake: index node has no stakes");
        require(stake.tokensAvailable >= _tokens, "Stake: not enough available tokens to unstake");
        // TODO: check epoch conditions, can unstake now?
        // TODO: take into account thawing period
        // TODO: how to take into account slashed funds? we could be below our balance...

        stake.tokens = stake.tokens.sub(_tokens);
        stake.tokensAvailable = stake.tokensAvailable.sub(_tokens);
        if (stake.tokens == 0) {
            delete stakes[indexNode];
        }

        require(token.transfer(indexNode, _tokens), "Stake: cannot transfer tokens");

        emit StakeUpdate(indexNode, stake.tokens);
    }

    /**
     * @dev Stake tokens on the index node
     * @param _indexNode Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexNode, uint256 _tokens) internal {
        Stakes.IndexNode storage stake = stakes[_indexNode];
        stake.tokens = stake.tokens.add(_tokens);
        stake.tokensAvailable = stake.tokensAvailable.add(_tokens);

        emit StakeUpdate(_indexNode, stake.tokens);
    }

    /**
     * @dev Return if channel for an allocation is active
     * @param _allocation Allocation data
     * @return True if payment channel related to allocation is active
     */
    function _isChannelActive(Stakes.Allocation memory _allocation) internal returns (bool) {
        return _allocation.status == Stakes.ChannelStatus.Active;
    }

    /**
     * @dev Track payment channel information for an allocation
     * @param _allocation Allocation data
     * @param _channelID Payment channel ID (xpub)
     */
    function _setupChannel(Stakes.Allocation storage _allocation, bytes memory _channelID)
        internal
    {
        require(channels[_channelID] == false, "Allocate: payment channel ID already in use");
        require(_isChannelActive(_allocation), "Allocate: payment channel must be closed");

        // Update channel
        _allocation.channelID = _channelID;
        _allocation.status = Stakes.ChannelStatus.Active;
        _allocation.createdAtEpoch = epochManager.currentEpoch();

        // Keep track of used xpubs
        channels[_channelID] = true;
    }

    /**
     * @dev Close payment channel related to allocation
     * @param _allocation Allocation data
     */
    function _closeChannel(Stakes.Allocation storage _allocation) internal {
        // Update channel
        _allocation.channelID = "";
        _allocation.status = Stakes.ChannelStatus.Closed;

        // Keep track of used xpubs
        channels[_allocation.channelID] = false;
    }
}
