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
    enum ChannelStatus { Active, Settled }

    struct Allocation {
        uint256 tokens; // Tokens allocated to a subgraph
        uint256 createdAtEpoch; // Epoch when it was created
        bytes xpub; // IndexNode xpub used in off-chain channel
        ChannelStatus status; // Current status
    }

    struct IndexNode {
        uint256 tokens; // Tokens on this stake (IndexNode + Delegators)
        uint256 tokensDelegated;
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

    // Percentage of index node stake to slash on disputes
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercentage;

    uint256 public maxSettlementDuration; // in epochs

    // IndexNode stake tracking
    mapping(address => Stakes.IndexNode) public stakes;

    // List of addresses allowed to slash stakes
    mapping(address => bool) public slashers;

    // Related contracts
    GraphToken public token;
    EpochManager public epochManager;

    // -- Events --

    event StakeUpdate(address indexed indexNode, uint256 tokens);

    event AllocationUpdate(
        address indexed indexNode,
        bytes32 indexed subgraphID,
        uint256 tokens
    );

    event SlasherUpdated(
        address indexed caller,
        address indexed slasher,
        bool enabled
    );

    modifier onlySlasher {
        require(slashers[msg.sender] == true, "Caller is not a Slasher");
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     * @param _token <address> - Address of the Graph Protocol token
     * @param _epochManager <address> - Address of the EpochManager contract
     * @param _maxSettlementDuration <uint256> - Max settlement duration
     * @param _slashingPercentage <uint256> - Percentage of index node stake slashed after a dispute
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

    function addSlasher(address _slasher) external onlyGovernor {
        slashers[_slasher] = true;
        emit SlasherUpdated(msg.sender, _slasher, true);
    }

    function removeSlasher(address _slasher) external onlyGovernor {
        slashers[_slasher] = false;
        emit SlasherUpdated(msg.sender, _slasher, false);
    }

    function setSlashingPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(
            _percentage >= 0,
            "Slashing percentage must above or equal to 0"
        );
        require(
            _percentage <= MAX_PPM,
            "Slashing percentage must be below or equal to MAX_PPM"
        );

        slashingPercentage = _percentage;
    }

    function isIndexNodeStaked(address _indexNode) public view returns (bool) {
        return getStakeTokens(_indexNode) > 0;
    }

    function getStakeTokens(address _indexNode) public view returns (uint256) {
        return stakes[_indexNode].tokens;
    }

    function getAllocation(address _indexNode, bytes32 _subgraphID)
        public
        view
        returns (Stakes.Allocation memory)
    {
        return stakes[_indexNode].allocations[_subgraphID];
    }

    function getSlashingAmount(address _indexNode)
        public
        view
        returns (uint256)
    {
        uint256 tokens = getStakeTokens(_indexNode);
        return slashingPercentage.mul(tokens).div(MAX_PPM); // slashingPercentage is in PPM
    }

    function slash(address _indexNode, uint256 _reward, address _beneficiary)
        external
        onlySlasher
    {
        // Beneficiary conditions
        require(
            _beneficiary != address(0),
            "Slash: beneficiary must not be an empty address"
        );
        require(_reward > 0, "Slash: reward must be greater than 0");

        // Get stake to be slashed
        uint256 stakeTokens = getStakeTokens(_indexNode);

        // Index node need to have stakes
        require(stakeTokens > 0, "Slash: index node has no stakes");

        // Slash stake
        uint256 tokensToSlash = getSlashingAmount(_indexNode);
        stakes[_indexNode].tokens = stakeTokens.sub(tokensToSlash);

        // Burn slashed index node stake, setting apart a reward for the beneficiary
        uint256 tokensToBurn = tokensToSlash.sub(_reward);
        token.burn(tokensToBurn);

        // Give the beneficiary a reward for slashing
        require(
            token.transfer(_beneficiary, _reward),
            "Slash: error sending dispute reward"
        );

        emit StakeUpdate(_indexNode, getStakeTokens(_indexNode));
    }

    /**
     * @dev Accept tokens and handle staking registration functions
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(
            msg.sender == address(token),
            "Caller is not the GRT token contract"
        );

        // Parse token received payload
        TokenReceiptAction option = TokenReceiptAction(
            _data.slice(0, 1).toUint8(0)
        );

        // Action according to payload
        if (option == TokenReceiptAction.Staking) {
            _stake(_from, _value);
        } else {
            revert("Token received option must be 0 or 1");
        }
        return true;
    }

    function allocate(bytes32 _subgraphID, uint256 _tokens, bytes calldata xpub)
        external
    {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];
        Stakes.Allocation storage allocation = stake.allocations[_subgraphID];

        require(
            stake.tokensAvailable >= _tokens,
            "Allocate: not enough available tokens"
        );

        stake.tokensAvailable = stake.tokensAvailable.sub(_tokens);
        allocation.createdAtEpoch = epochManager.currentEpoch();
        allocation.status = Stakes.ChannelStatus.Active;
        allocation.tokens = allocation.tokens.add(_tokens);
        allocation.xpub = xpub;

        emit AllocationUpdate(indexNode, _subgraphID, allocation.tokens);
    }

    function unallocate(bytes32 _subgraphID) external {
        address indexNode = msg.sender;

        // TODO
        // check subgraph allocation exist
        // check balances are enough
        // check epoch conditions, can unallocate now?
        // move balances to the main stack
    }

    function unstake(bytes32 _subgraphID, uint256 _tokens) external {
        address indexNode = msg.sender;
        Stakes.IndexNode storage stake = stakes[indexNode];

        require(
            stake.tokens >= _tokens,
            "Stake: not enough tokens to unallocate"
        );

        stake.tokens = stake.tokens.sub(_tokens);
        stake.tokensAvailable = stake.tokensAvailable.sub(_tokens);
        if (stake.tokens == 0) {
            delete stakes[indexNode];
        }

        // TODO
        // check index stake exist
        // check balances are enough
        // check epoch conditions, can unstake now?
        // transfer tokens to indexNode
    }

    /**
     * @dev Stake Graph Tokens on IndexNode
     * @param _indexNode <address> - Address of staking party
     * @param _tokens <uint256> - Amount of Graph Tokens to be staked
     */
    function _stake(address _indexNode, uint256 _tokens) internal {
        Stakes.IndexNode storage stake = stakes[_indexNode];
        stake.tokens = stake.tokens.add(_tokens);
        stake.tokensAvailable = stake.tokensAvailable.add(_tokens);

        emit StakeUpdate(_indexNode, stake.tokens);
    }
}
