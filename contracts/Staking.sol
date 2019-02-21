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

contract Staking is Governed {

    /* Structs */
    struct Curator {
        uint256 amountStaked;
    }
    struct IndexingNode {
        uint256 amountStaked;
    }
    struct Subgraph {
        uint256 totalCurationStake;
        uint256 totalIndexingStake;
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
    mapping (bytes32 => address[]) public subgraphCurators;

    // Mapping subgraphId to list of addresses to Indexing Nodes
    // These mappings work together
    mapping (address => IndexingNode) public indexingNodes;
    mapping (bytes32 => address[]) public subgraphIndexingNodes;

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
     * @param _token <address> - Graph Token address
     * @param _data <bytes> - Data to parse and handle registration functions
     */
    function receiveToken (
        address _from,
        uint256 _value,
        bytes memory _data
    )
        external
        returns (bool success)
    {
    }

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Curator is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     */
    // @todo: Require _value >= minimumCurationStakingAmount
    function stakeGraphTokensForCuration (
        bytes32 _subgraphId,
        address _staker,
        uint256 _value
    )
        private
    {
    }

    /**
     * @dev Stake Graph Tokens for Indexing Node data retrieval by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     * @param _indexingRecords <bytes> - Index Records of the indexes being stored
     */
    // @todo: Require _value >= setMinimumIndexingStakingAmount
    function stakeGraphTokensForIndexing (
        bytes32 _subgraphId,
        address _staker,
        uint256 _value,
        bytes memory _indexingRecords
    )
        private
    {
    }

    /**
     * @dev Arbitrator (governance) can slash staked Graph Tokens in dispute
     * @param _disputeId <bytes> Hash of readIndex data + disputer data
     */
    function slashStake (
        bytes memory _disputeId
    )
        public
        onlyArbitrator
        returns (bool success)
    {
        success = true;
    }
}
