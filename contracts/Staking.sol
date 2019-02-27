pragma solidity ^0.5.2;

/*
 * @title Staking contract
 *
 * @author Bryant Eisenbach
 * @author Reuven Etzion
 *
 * Curator Requirements
 * @req c01 Any User can stake Graph Tokens to be included as a Curator for a given subgraphId.
 * @req c02 The amount of tokens to stake required to become a Curator must be greater than or
 *          equal to the minimum curation staking amount.
 * @req c03 Only Governance can change the minimum curation staking amount.
 * @req c04 A Curator is issued shares according to a pre-defined bonding curve depending on
 *          equal to the total amount of Curation stake for a given subgraphId if they
 *          successfully stake on a given subgraphId.
 *
 * Indexer Requirements
 * @req i01 Any User can stake Graph Tokens to be included as an Indexer for a given subgraphId.
 * @req i02 The amount of tokens to stake required to become an Indexer must be greater than or
 *          equal to the minimum indexing staking amount.
 * @req i03 Only Governance can change the minimum indexing staking amount.
 * @req i04 If the number of Indexers is greater than or equal to the maximum number of indexers,
 *          the amount of tokens required to become an Indexer must be more than the lowest stake.
 * @req i05 Only Governance can change the maximum number of indexers.
 * @req i06 If an Indexer is no longer staking more than the lowest stake, and there are more than
 *          the maximum number of indexers, they are allowed to withdraw their stake after a pre-
 *          defined cooling period has completed.
 *
 * Slashing Requirements
 * @req s01 The Dispute Manager contract can burn the staked Tokens of any Indexer.
 * @req s02 Only Governance can change the Dispute Manager contract address.
 *
 * @notice Indexing Nodes who have staked for a dataset, are not limited by the protocol in how
 *         many read requests they may process for that dataset. However, it may be assumed that
 *         Indexing Nodes with higher deposits will receive more read requests and thus collect
 *         more fees, all else being equal, as this represents a greater economic security margin
 *         to the end user.
 *
 */

import "./GraphToken.sol";
import "./Governed.sol";
import "./DisputeManager.sol";
import "bytes/BytesLib.sol";

contract Staking is Governed, TokenReceiver
{
    using BytesLib for bytes;

    /* Structs */
    struct Curator {
        uint256 amountStaked;
    }
    struct IndexingNode {
        uint256 amountStaked;
        mapping (bytes32 => bool) indexerForSubgraph;
    }
    struct Subgraph {
        uint256 totalCurationStake;
        uint256 totalIndexingStake;
        uint256 totalIndexers;
    }

    /* STATE VARIABLES */
    // Minimum amount allowed to be staked by Market Curators
    uint256 public minimumCurationStakingAmount;

    // Minimum amount allowed to be staked by Indexing Nodes
    uint256 public minimumIndexingStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider 
    uint256 public maximumIndexers;

    // Mapping subgraphId to list of addresses to Curators
    // These mappings work together
    mapping (address => Curator) public curators;

    // Mapping subgraphId to list of addresses to Indexing Nodes
    // These mappings work together
    mapping (address => IndexingNode) public indexingNodes;

    // Subgraphs mapping
    mapping (bytes32 => Subgraph) subgraphs;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Graph Token address
    GraphToken public token;

    uint constant COOLING_PERIOD = 7 days;

    // Only the designated arbitrator
    modifier onlyArbitrator () {
        require(msg.sender == arbitrator);
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     */
    constructor (
        address _governor,
        address _token
    )
        public
        Governed(_governor)
    {
        // Governance Parameter Defaults
        maximumIndexers = 10;
        minimumCurationStakingAmount = 100;  // Tokens
        minimumIndexingStakingAmount = 100;  // Tokens
        token = GraphToken(_token);
    }

    /**
     * @dev Set the Minimum Staking Amount for Market Curators
     * @param _minimumCurationStakingAmount <uint256> - Minimum amount allowed to be staked
     * for Curation
     */
    function setMinimumCurationStakingAmount (
        uint256 _minimumCurationStakingAmount
    )
        external
        onlyGovernance
        returns (bool success)
    {
        minimumCurationStakingAmount = _minimumCurationStakingAmount;  // Tokens
        return true;
    }

    /**
     * @dev Set the Minimum Staking Amount for Indexing Nodes
     * @param _minimumIndexingStakingAmount <uint256> - Minimum amount allowed to be staked
     * for Indexing Nodes
     */
    function setMinimumIndexingStakingAmount (
        uint256 _minimumIndexingStakingAmount
    )
        external
        onlyGovernance
        returns (bool success)
    {
        minimumIndexingStakingAmount = _minimumIndexingStakingAmount;  // Tokens
        return true;
    }

    /**
     * @dev Set the maximum number of Indexing Nodes
     * @param _maximumIndexers <uint256> - Maximum number of Indexing Nodes allowed
     */
    function setMaximumIndexers (
        uint256 _maximumIndexers
    )
        external
        onlyGovernance
        returns (bool success)
    {
        maximumIndexers = _maximumIndexers;
        return true;
    }

    /**
     * @dev Accept tokens and handle staking registration functions
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     * @param _data <bytes> - Data to parse and handle registration functions
     */
    function receiveToken (
        address _from,
        uint256 _value,
        bytes calldata _data
    )
        external
        returns (bool success)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token));

        // Process _data to figure out the action to take (and which subgraph is involved)
        require(_data.length >= 1+32); // Must be at least 33 bytes
        bool _stakeForCuration = _data.slice(0, 1).toUint(0) == 1;
        bytes32 _subgraphId = _data.slice(1, 32).toBytes32(0);

        if (_stakeForCuration) {
            // Handle internal call for Curation Staking
            stakeGraphTokensForCuration(_subgraphId, _from, _value);
        } else {
            // Slice the rest of the data as indexing records
            bytes memory _indexingRecords = _data.slice(33, _data.length-33);
            // Ensure that the remaining data is parse-able for indexing records
            require(_indexingRecords.length % 32 == 0);
            // Handle internal call for Index Staking
            stakeGraphTokensForIndexing(_subgraphId, _from, _value, _indexingRecords);
        }
        success = true;
    }

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Curator is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     */
    function stakeGraphTokensForCuration (
        bytes32 _subgraphId,
        address _staker,
        uint256 _value
    )
        private
    {
        require(_value >= minimumCurationStakingAmount);
        curators[_staker].amountStaked += _value;
        subgraphs[_subgraphId].totalCurationStake += _value;
    }

    /**
     * @dev Stake Graph Tokens for Indexing Node data retrieval by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     * @param _indexingRecords <bytes> - Index Records of the indexes being stored
     */
    function stakeGraphTokensForIndexing (
        bytes32 _subgraphId,
        address _staker,
        uint256 _value,
        bytes memory _indexingRecords
    )
        private
    {
        require(_value >= minimumIndexingStakingAmount); // @imp i02
        require(subgraphs[_subgraphId].totalIndexers < maximumIndexers);
        indexingNodes[_staker].amountStaked += _value;
        subgraphs[_subgraphId].totalIndexingStake += _value;
        indexingNodes[_staker].indexerForSubgraph[_subgraphId] = true;
        subgraphs[_subgraphId].totalIndexers += 1;
    }

    /**
     * @dev Arbitrator (governance) can slash staked Graph Tokens in dispute
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     * @param _staker <address> - Address of Staking party that is being slashed
     * @param _disputeId <bytes> - Hash of readIndex data + disputer data
     */
    function slashStake (
        bytes32 _subgraphId,
        address _staker,
        bytes memory _disputeId
    )
        public
        onlyArbitrator
        returns (bool success)
    {
        require(indexingNodes[_staker].indexerForSubgraph[_subgraphId]);
        uint256 _value = indexingNodes[_staker].amountStaked;
        require(_value > 0);
        indexingNodes[_staker].amountStaked = 0;
        subgraphs[_subgraphId].totalIndexingStake -= _value;
        indexingNodes[_staker].indexerForSubgraph[_subgraphId] = false;
        subgraphs[_subgraphId].totalIndexers -= 1;
        token.burn(_value);
        success = true;
    }
}
