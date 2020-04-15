pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Staking contract
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./EpochManager.sol";
import "./libs/Stakes.sol";
import "./bytes/BytesLib.sol";


contract Staking is Governed {
    using BytesLib for bytes;
    using SafeMath for uint256;
    using Stakes for Stakes.IndexNode;
    using Stakes for Stakes.Allocation;

    // -- Stakes --

    enum TokenReceiptAction { Staking, Settlement }

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;
    // -- State --

    uint256 public maxSettlementDuration; // in epochs

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
    event StakeLocked(address indexed indexNode, uint256 tokens, uint256 until);
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
     */
    constructor(
        address _governor,
        address _token,
        address _epochManager,
        uint256 _maxSettlementDuration,
        uint256 _thawingPeriod
    ) public Governed(_governor) {
        token = GraphToken(_token);
        epochManager = EpochManager(_epochManager);
        maxSettlementDuration = _maxSettlementDuration;
        thawingPeriod = _thawingPeriod;
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
        return stakes[_indexNode].hasTokens();
    }

    /**
     * @dev Get the total amount of tokens staked by the index node
     * @param _indexNode Address of the index node
     * @return Amount of tokens staked by the index node
     */
    function getIndexNodeStakeTokens(address _indexNode) public view returns (uint256) {
        return stakes[_indexNode].tokens;
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
     * @param _tokens Amount of tokens to slash from the index node stake
     * @param _reward Amount of reward tokens to send to a beneficiary
     * @param _beneficiary Address of a beneficiary to receive a reward for the slashing
     */
    function slash(address _indexNode, uint256 _tokens, uint256 _reward, address _beneficiary)
        external
        onlySlasher
    {
        uint256 tokensToSlash = _tokens;
        Stakes.IndexNode storage stake = stakes[_indexNode];

        require(stake.hasTokens(), "Slash: index node has no stakes");
        require(_beneficiary != address(0), "Slash: beneficiary must not be an empty address");
        require(tokensToSlash >= _reward, "Slash: reward cannot be higher than slashed amount");

        // Slash stake
        stake.releaseTokens(tokensToSlash);

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        uint256 tokensToBurn = tokensToSlash.sub(_reward);
        if (tokensToBurn > 0) {
            token.burn(tokensToBurn);
        }

        // Give the beneficiary a reward for slashing
        if (_reward > 0) {
            require(token.transfer(_beneficiary, _reward), "Slash: error sending dispute reward");
        }

        emit StakeUpdate(_indexNode, stake.tokens);
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
        } else if (option == TokenReceiptAction.Settlement) {
            // TODO: settlement
        } else {
            revert("Token received option must be 0 or 1");
        }
        return true;
    }

    /**
     * @dev Allocate available tokens to a subgraph
     * @param _subgraphID ID of the subgraph where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelID ID used to identify off-chain payment channels
     */
    function allocate(bytes32 _subgraphID, uint256 _tokens, bytes calldata _channelID) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(stake.hasTokens(), "Allocate: index node has no stakes");
        require(
            stake.tokensAvailable() >= _tokens,
            "Allocate: not enough tokens available to allocate"
        );

        Stakes.Allocation storage alloc = stake.allocateTokens(_subgraphID, _tokens);
        _setupChannel(alloc, _channelID);

        emit AllocationUpdate(indexNode, _subgraphID, alloc.tokens);
    }

    /**
     * @dev Unallocate tokens from a subgraph
     * @param _subgraphID ID of the subgraph where tokens are allocated
     * @param _tokens Amount of tokens to unallocate
     */
    function unallocate(bytes32 _subgraphID, uint256 _tokens) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];
        Stakes.Allocation storage alloc = stake.allocations[_subgraphID];

        require(_tokens > 0, "Allocate: tokens to unallocate cannot be zero");
        require(alloc.tokens > 0, "Allocate: no tokens allocated to the subgraph");
        require(alloc.tokens >= _tokens, "Allocate: not enough tokens available in the subgraph");
        require(alloc.hasActiveChannel() == false, "Allocate: channel must be closed");

        stake.unallocateTokens(_subgraphID, _tokens);

        emit AllocationUpdate(indexNode, _subgraphID, alloc.tokens);
    }

    /**
     * @dev Unstake tokens from the index node stake, lock them until thawning period expires
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(stake.hasTokens(), "Stake: index node has no stakes");
        require(
            stake.tokensAvailable() >= _tokens,
            "Stake: not enough tokens available to unstake"
        );

        stake.lockTokens(_tokens, thawingPeriod);

        emit StakeLocked(indexNode, stake.tokensLocked, stake.tokensLockedUntil);
    }

    /**
     * @dev Withdraw tokens once the thawning period has passed
     */
    function withdraw() external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        uint256 tokensToWithdraw = stake.withdrawTokens();
        require(tokensToWithdraw > 0, "Stake: no tokens available to withdraw");

        require(token.transfer(indexNode, tokensToWithdraw), "Stake: cannot transfer tokens");

        emit StakeUpdate(indexNode, stake.tokens);
    }

    /**
     * @dev Stake tokens on the index node
     * @param _indexNode Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexNode, uint256 _tokens) internal {
        Stakes.IndexNode storage stake = stakes[_indexNode];

        stake.depositTokens(_tokens);

        emit StakeUpdate(_indexNode, stake.tokens);
    }

    /**
     * @dev Track payment channel information for an allocation
     * @param _alloc Allocation data
     * @param _channelID Payment channel ID
     */
    function _setupChannel(Stakes.Allocation storage _alloc, bytes memory _channelID) internal {
        require(channels[_channelID] == false, "Allocate: payment channel ID already in use");
        require(_alloc.hasActiveChannel() == false, "Allocate: payment channel must be closed");

        // TODO: deploy multisig contract from factory
        // - I need the address of the proxy contract deployed (param)
        // - I need to call createProxyWithNonce(mastercopy, initializer, saltNonce)
        //   - mastercopy: address of the deployed MinimumViableMultisig ()
        //   - initializer: 0x
        //   - saltNonce: 0

        // Update channel
        _alloc.channelID = _channelID;
        _alloc.status = Stakes.ChannelStatus.Active;
        _alloc.createdAtEpoch = epochManager.currentEpoch();

        // Keep track of used
        channels[_channelID] = true;
    }

    /**
     * @dev Close payment channel related to allocation
     * @param _alloc Allocation data
     */
    function _closeChannel(Stakes.Allocation storage _alloc) internal {
        // Update channel
        _alloc.channelID = "";
        _alloc.status = Stakes.ChannelStatus.Closed;

        // Keep track of used
        channels[_alloc.channelID] = false;
    }
}
