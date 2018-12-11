pragma solidity ^0.5.1;

import "./Ownable.sol";

contract Staking is Ownable {
    
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
    * @req 01 State variable minimumStakingAmount is editable by Governance
    * @req 02 State variable maxIndexers is editable by Governance
    * @req 03 Indexing Nodes can stake Graph Tokens for Data Retrieval for subgraphId
    * @req 04 Curator can stake Graph Tokens for subgraphId
    * ...
    */

    /* STATE VARIABLES */
    // Minimum amount allowed to be staked
    uint public minimumStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider 
    uint public maxIndexers;

    // Storage of staking amount for each Curator
    mapping (address => uint) public curatorStakingAmount;

    // Storage of staking amount for each Indexing Node
    mapping (address => uint) public indexingNodeStakingAmount;
     
}