pragma solidity ^0.5.2;

import "./GraphToken.sol";
import "./Governed.sol";
import "./DisputeManager.sol";

contract Staking is Governed {
    
    /* 
    * @title Staking contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Indexing Nodes stake Graph Tokens to participate in the data retrieval market for a
    * specific subgraph, as identified by subgraphId.
    *
    * Curators stake Graph Tokens to participate in a specific curation market,
    * as identified by subgraphId
    *
    * For a stakingAmount to be considered valid, it must meet the following requirements:
    * - stakingAmount >= minimumStakingAmount where minimumStakingAmount is set via governance.
    * - The stakingAmount must be in the set of the top N staking amounts, where N is determined by
    *   the maxIndexers parameter which is set via governance.
    * 
    * Indexing Nodes who have staked for a dataset, are not limited by the protocol in how many
    * read requests they may process for that dataset. However, it may be assumed that Indexing
    * Nodes with higher deposits will receive more read requests and thus collect more fees, all
    * else being equal, as this represents a greater economic security margin to the end user.
    * 
    * Requirements ("Staking" contract):
    * req 01 State variables minimumCurationStakingAmount, minimumIndexingStakingAmount, & maxIndexers are editable by Governance
    * req 02 Indexing Nodes can stake Graph Tokens for Data Retrieval for subgraphId
    * req 03 Curator can stake Graph Tokens for subgraphId
    * req 04 Staking amounts must meet criteria specified in technical spec, mechanism design section.
    * req 05 Dispute Resolution can slash staked tokens
    * ...
    */

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
    uint256 public maxIndexers;

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

    // Only the designated arbitrator
    modifier onlyArbitrator () {
        require(msg.sender == arbitrator);
        _;
    }

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     */
    constructor (address _governor) public Governed (_governor) {}

    /**
     * @dev Set the Minimum Staking Amount for Market Curators
     * @param _minimumCurationStakingAmount <uint256> - Minimum amount allowed to be staked for Curation
     */
    function setMinimumCurationStakingAmount (uint256 _minimumCurationStakingAmount) public onlyGovernance returns (bool success)
    {
        revert();
    }

    /**
     * @dev Set the Minimum Staking Amount for Indexing Nodes
     * @param _minimumIndexingStakingAmount <uint256> - Minimum amount allowed to be staked for Indexing Nodes
     */
    function setMinimumIndexingStakingAmount (uint256 _minimumIndexingStakingAmount) public onlyGovernance returns (bool success)
    {
        revert();
    }

    /**
     * @dev Set the maximum number of Indexing Nodes
     * @param _maximumIndexers <uint256> - Maximum number of Indexing Nodes allowed
     */
    function setMaximumIndexers (uint256 _maximumIndexers) public onlyGovernance returns (bool success)
    {
        revert();
    }

    /* Graph Protocol Functions */
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
    ) public returns (bool success)
    {
        revert();
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
    ) public returns (bool success)
    {
        revert();
    }

    /**
     * @dev Receive approval to spend Graph Tokens of someone else
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens 
     * @param _token <address> - Graph Token address
     * @notice How does this actually work? Does it not need other functions?
     * ref https://ethereum.stackexchange.com/questions/12852/could-somebody-please-explain-in-detail-what-this-ethereum-contract-is-doing
     */
    function receiveApproval (
        address _from,
        uint256 _value,
        address _token,
        bytes memory _data
    ) public
    {
        revert();
    }

    /**
     * @dev Arbitrator (governance) can slash staked Graph Tokens in dispute
     * @param _disputeId <bytes> Hash of readIndex data + disputer data
     */
    function slashStake (bytes memory _disputeId) public onlyArbitrator returns (bool success)
    {
        revert();
    }

    // WIP...
     
}
