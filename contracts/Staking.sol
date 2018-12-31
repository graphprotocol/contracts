pragma solidity ^0.5.2;

import "./GraphToken.sol";
import "./Ownable.sol";
import "./BurnableERC20.sol";

contract Staking is Owned {
    
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
    * @req 01 State variables minimumCurationStakingAmount, minimumIndexingStakingAmount, & maxIndexers are editable by Governance
    * @req 02 Indexing Nodes can stake Graph Tokens for Data Retrieval for subgraphId
    * @req 03 Curator can stake Graph Tokens for subgraphId
    * @req 04 Staking amounts must meet criteria specified in technical spec, mechanism design section.
    * @req 05 Dispute Resolution can slash staked tokens
    * ...
    */

    /* STATE VARIABLES */
    // Minimum amount allowed to be staked by Market Curators
    uint public minimumCurationStakingAmount;

    // Minimum amount allowed to be staked by Indexing Nodes
    uint public minimumIndexingStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider 
    uint public maxIndexers;

    // Storage of staking amount for each Curator
    mapping (address => uint) public curatorStakingAmount;

    // Storage of staking amount for each Indexing Node
    mapping (address => uint) public indexingNodeStakingAmount;

    /* Graph Token governed variables */
    /**
     * @dev Set the Minimum Staking Amount for Market Curators
     * @param _minimumCurationStakingAmount <uint> - Minimum amount allowed to be staked for Curation
     */
    function setMinimumCurationStakingAmount (uint _minimumCurationStakingAmount) public onlyOwner returns (bool success) {}

    /**
     * @dev Set the Minimum Staking Amount for Indexing Nodes
     * @param _minimumIndexingStakingAmount <uint> - Minimum amount allowed to be staked for Indexing Nodes
     */
    function setMinimumIndexingStakingAmount (uint _minimumIndexingStakingAmount) public onlyOwner returns (bool success) {}

    /**
     * @dev Set the maximum number of Indexing Nodes
     * @param _maximumIndexers <uint> - Maximum number of Indexing Nodes allowed
     */
    function setMaximumIndexers (uint _maximumIndexers) public onlyOwner returns (bool success) {}

    /* Graph Protocol Functions */
    /**
     * @dev Stake Graph Tokens for Indexing Node data retrieval by subgraphId
     * @param _subgraphId <string> - Subgraph ID the Indexing Node is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint> - Amount of Graph Tokens to be staked
     */
    // @todo: Require _value >= setMinimumIndexingStakingAmount
    function stakeGraphTokensForIndexing (
        string memory _subgraphId, 
        address _staker, 
        uint _value
    ) public returns (bool success) {}

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphId
     * @param _subgraphId <string> - Subgraph ID the Curator is staking Graph Tokens for
     * @param _staker <address> - Address of Staking party
     * @param _value <uint> - Amount of Graph Tokens to be staked
     */
    // @todo: Require _value >= minimumCurationStakingAmount
    function stakeGraphTokensForCuration (
        string memory _subgraphId, 
        address _staker, 
        uint _value
    ) public returns (bool success);

    function receiveApproval (
        address _from, // sender
        uint256 _tokens, // value
        address payable _token, // Graph Token address
        bytes memory _data
    ) public {

        // @security - best practice - transferFrom will return false but not throw, so we use assert
        // assert(StandardERC20Token(_token).tranferFrom(_from, address(this), _tokens));
        
        // parse data to determine if we are staking Indexing or Curation
        // if (_data.length > 0) {
        //     string memory _subgraphId = bytes32ToString(_data);
        //     stakeGraphTokensForIndexing(
        //         _subgraphId, // parse subgraphId
        //         _from, // staker
        //         _tokens // value
        //     );
        // }
        // else {
        //     stakeGraphTokensForCuration();
        // }


    }

    // Parse binary data to string
    function bytes32ToString(bytes32 _data) public pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(_data) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

    // WIP...
     
}