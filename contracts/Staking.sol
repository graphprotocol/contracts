pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Staking contract
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./EpochManager.sol";
import "./libs/Rebates.sol";
import "./libs/Stakes.sol";
import "./bytes/BytesLib.sol";
import "./channel/funding/proxies/ProxyFactory.sol";


contract Staking is Governed {
    using BytesLib for bytes;
    using SafeMath for uint256;
    using Stakes for Stakes.IndexNode;
    using Stakes for Stakes.Allocation;
    using Rebates for Rebates.Pool;

    // -- Stakes --

    struct Channel {
        address indexNode;
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

    // Need to pass this period for delegators to settle
    uint256 public maxSettlementDuration; // in epochs

    // Time in blocks to unstake
    uint256 public thawingPeriod;

    // Total tokens staked in the protocol
    uint256 public totalTokens;

    // Total fees collected outstanding in the protocol
    uint256 public totalFees;

    // IndexNode stake tracking
    mapping(address => Stakes.IndexNode) public stakes;

    // Payment channels
    mapping(address => Channel) public channels;

    // Rebate pool
    mapping(uint256 => Rebates.Pool) public rebates;

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // Related contracts
    GraphToken public token;
    EpochManager public epochManager;
    address public curation;

    ProxyFactory public channelFactory;
    address public channelMaster;
    address public channelHub;

    // -- Events --

    event StakeUpdate(address indexed indexNode, uint256 tokens, uint256 total);
    event StakeLocked(address indexed indexNode, uint256 tokens, uint256 until);

    event AllocationUpdated(
        address indexed indexNode,
        bytes32 indexed subgraphID,
        uint256 epoch,
        uint256 tokens,
        address channelID
    );
    // TODO: consider adding curation reward
    event AllocationSettled(
        address indexed indexNode,
        bytes32 indexed subgraphID,
        uint256 epoch,
        uint256 tokens,
        address channelID
    );

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
     * @param _curation Address of the Curation contract
     * @param _maxSettlementDuration Max settlement duration
     * @param _thawingPeriod Period in blocks to wait for token withdrawals after unstaking
     * @param _channelFactory Address of the factory contract to deploy channel multisig
     * @param _channelMaster Address of the contract to use as template for multisig
     * @param _channelHub Address of the payment channel hub
     */
    constructor(
        address _governor,
        address _token,
        address _epochManager,
        address _curation,
        uint256 _maxSettlementDuration,
        uint256 _thawingPeriod,
        address _channelFactory,
        address _channelMaster,
        address _channelHub
    ) public Governed(_governor) {
        token = GraphToken(_token);
        epochManager = EpochManager(_epochManager);
        curation = _curation;

        maxSettlementDuration = _maxSettlementDuration;
        thawingPeriod = _thawingPeriod;

        channelFactory = ProxyFactory(_channelFactory);
        channelMaster = _channelMaster;
        channelHub = _channelHub;
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

        require(stake.hasTokens(), "Slashing: index node has no stakes");
        require(_beneficiary != address(0), "Slashing: beneficiary must not be an empty address");
        require(tokensToSlash >= _reward, "Slashing: reward cannot be higher than slashed amount");

        // Slash stake
        stake.releaseTokens(tokensToSlash);

        // Set apart the reward for the beneficiary and burn remaining slashed stake
        uint256 tokensToBurn = tokensToSlash.sub(_reward);
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

        emit StakeUpdate(_indexNode, tokensToSlash, stake.tokens);
    }

    /**
     * @dev Accept tokens and handle staking registration functions
     * @param _from Token holder's address
     * @param _value Amount of Graph Tokens
     */
    function tokensReceived(
        address _from,
        uint256 _value,
        bytes calldata /*_data*/
    ) external returns (bool) {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token), "Caller is not the GRT token contract");

        // If we receive funds from a channel multisig it is a settle
        Channel storage channel = channels[_from];
        if (channel.indexNode != address(0)) {
            _settle(channel, _value);
            return true;
        }

        // Any other case is a staking of funds
        _stake(_from, _value);
        return true;
    }

    /**
     * @dev Allocate available tokens to a subgraph
     * @param _subgraphID ID of the subgraph where tokens will be allocated
     * @param _tokens Amount of tokens to allocate
     * @param _channelOwner The address used by the IndexNode to setup the off-chain payment channel
     */
    function allocate(bytes32 _subgraphID, uint256 _tokens, address _channelOwner) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(stake.hasTokens(), "Allocation: index node has no stakes");
        require(
            stake.tokensAvailable() >= _tokens,
            "Allocation: not enough tokens available to allocate"
        );
        require(
            stake.hasAllocation(_subgraphID) == false,
            "Allocation: cannot allocate if already allocated"
        );
        // TODO: should index node be able to allocate more at any time?

        // Account new allocation
        Stakes.Allocation storage alloc = stake.allocateTokens(_subgraphID, _tokens);

        // Setup channel
        address channelID = _setupChannel(alloc, _channelOwner);
        channels[channelID] = Channel(indexNode, _subgraphID);

        emit AllocationUpdated(
            indexNode,
            _subgraphID,
            alloc.createdAtEpoch,
            alloc.tokens,
            channelID
        );
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

        require(_tokens > 0, "Allocation: tokens to unallocate cannot be zero");
        require(alloc.tokens > 0, "Allocation: no tokens allocated to the subgraph");
        require(alloc.tokens >= _tokens, "Allocation: not enough tokens available in the subgraph");
        require(alloc.hasActiveChannel() == false, "Allocation: channel must be closed");
        // TODO: should this only happen before one epoch?

        // Account new allocation
        stake.unallocateTokens(_subgraphID, _tokens);
        // TODO: should we delete alloc if empty?

        emit AllocationUpdated(
            indexNode,
            _subgraphID,
            epochManager.currentEpoch(),
            alloc.tokens,
            alloc.channelID
        );
    }

    /**
     * @dev Unstake tokens from the index node stake, lock them until thawning period expires
     * @param _tokens Amount of tokens to unstake
     */
    function unstake(uint256 _tokens) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(stake.hasTokens(), "Staking: index node has no stakes");
        require(
            stake.tokensAvailable() >= _tokens,
            "Staking: not enough tokens available to unstake"
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
        require(tokensToWithdraw > 0, "Staking: no tokens available to withdraw");

        totalTokens = totalTokens.sub(tokensToWithdraw);

        require(token.transfer(indexNode, tokensToWithdraw), "Staking: cannot transfer tokens");

        emit StakeUpdate(indexNode, tokensToWithdraw, stake.tokens);
    }

    /**
     * @dev Claim tokens from the rebate pool
     * @param _epoch Epoch of the rebate pool we are claiming tokens from
     * @param _subgraphID Subgraph we are claiming tokens from
     */
    function claim(uint256 _epoch, bytes32 _subgraphID) external {
        address indexNode = msg.sender;
        Rebates.Pool storage pool = rebates[_epoch];
        Rebates.Settlement storage settlement = pool.settlements[indexNode][_subgraphID];

        require(settlement.allocation > 0, "Rebate: settlement does not exist");

        uint256 tokensToClaim = pool.releaseTokens(indexNode, _subgraphID);
        require(tokensToClaim > 0, "Rebate: no tokens available to claim");

        totalFees = totalFees.sub(tokensToClaim);

        // TODO: support re-staking
        require(token.transfer(indexNode, tokensToClaim), "Rebate: cannot transfer tokens");

        // TODO: emit event
    }

    /**
     * @dev Stake tokens on the index node
     * @param _indexNode Address of staking party
     * @param _tokens Amount of tokens to stake
     */
    function _stake(address _indexNode, uint256 _tokens) private {
        Stakes.IndexNode storage stake = stakes[_indexNode];

        stake.depositTokens(_tokens);
        totalTokens = totalTokens.add(_tokens);

        emit StakeUpdate(_indexNode, _tokens, stake.tokens);
    }

    /**
     * @dev Settle a channel after receiving collected query fees from it
     * @param _channel Channel multisig contract
     * @param _tokens Amount of tokens to stake
     */
    function _settle(Channel storage _channel, uint256 _tokens) private {
        address indexNode = _channel.indexNode;
        bytes32 subgraphID = _channel.subgraphID;
        Stakes.IndexNode storage stake = stakes[indexNode];
        Stakes.Allocation storage alloc = stake.allocations[subgraphID];
        require(alloc.hasActiveChannel(), "Channel: Must be active for settlement");

        // Epoch conditions
        uint256 currentEpoch = epochManager.currentEpoch();
        uint256 epochs = currentEpoch.sub(alloc.createdAtEpoch);
        require(epochs > 0, "Channel: Can only settle after one epoch passed");

        // Send part of the funds to the curator subgraph curve
        uint256 fees = _tokens;
        uint256 curationFees = curationPercentage.mul(_tokens).div(MAX_PPM);
        fees = fees.sub(curationFees);
        require(
            token.transferToTokenReceiver(curation, curationFees, abi.encodePacked(subgraphID)),
            "Channel: Could not transfer tokens to Curators"
        );

        // Set apart fees into a rebate pool
        Rebates.Pool storage pool = rebates[currentEpoch];
        pool.depositTokens(
            indexNode,
            subgraphID,
            fees,
            alloc.getTokensEffectiveAllocation(epochs, maxSettlementDuration)
        );

        // Update global counter of collected fees
        totalFees = totalFees.add(fees);

        // Close channel
        stake.unallocateTokens(subgraphID, alloc.tokens);
        address channelID = _closeChannel(alloc);
        delete channels[channelID];

        emit AllocationSettled(indexNode, subgraphID, currentEpoch, _tokens, channelID);
    }

    /**
     * @dev Track payment channel information for an allocation
     * @param _alloc Allocation data
     * @param _channelOwner Address of the channel initiating party
     */
    function _setupChannel(Stakes.Allocation storage _alloc, address _channelOwner)
        private
        returns (address)
    {
        // ChannelID (multisig contract address) for IndexNode<->Hub
        address channelID = _createChannelID(_channelOwner);
        require(channels[channelID].indexNode == address(0), "Channel: channel ID already in use");

        // Update channel
        _alloc.channelID = channelID;
        _alloc.status = Stakes.ChannelStatus.Active;
        _alloc.createdAtEpoch = epochManager.currentEpoch();

        return channelID;
    }

    /**
     * @dev Close payment channel related to allocation
     * @param _alloc Allocation data
     */
    function _closeChannel(Stakes.Allocation storage _alloc) private returns (address) {
        address channelID = _alloc.channelID;

        // Update channel
        _alloc.channelID = address(0);
        _alloc.createdAtEpoch = 0;
        _alloc.status = Stakes.ChannelStatus.Closed;

        return channelID;
    }

    /**
     * @dev Create a multisig contract using CREATE2 with signers (channelOwner, channelHub)
     * @dev The address of this contract must match the one created in the counterfactual payment channel
     * @return Address of the multisig contract
     */
    function _createChannelID(address _channelOwner) private returns (address) {
        // Deploy multisig from a factory contract
        //   - mastercopy: address of the deployed MinimumViableMultisig
        //   - initializer: setup multisig with signers (IndexNode and Hub)
        //   - saltNonce: number to have multiple channels per (IndexNode, Hub)
        // NOTE: nonce is fixed to 0 as per Connext convention
        // NOTE: setup(address[] memory) -> 0xfdf55b99
        bytes memory initializer = abi.encodeWithSelector(0xfdf55b99, [_channelOwner, channelHub]);
        uint256 nonce = 0;
        bytes32 salt = keccak256(abi.encodePacked(_getChainID(), nonce));
        return
            address(channelFactory.createProxyWithNonce(channelMaster, initializer, uint256(salt)));
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
