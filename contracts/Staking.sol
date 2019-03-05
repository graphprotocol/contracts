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
 * @req i04 An Indexer can start the process of removing their stake for a given subgraphId at
 *          any time.
 * @req i05 An Indexer may withdraw their stake for a given subgraphId after the process has
 *          been started and a cooling period has elapsed.
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

    /* Events */
    event CurationNodeStaked (
        address indexed staker,
        uint256 amountStaked
    );

    event IndexingNodeStaked (
        address indexed staker,
        uint256 amountStaked
    );

    event IndexingNodeLogOut (
        address indexed staker
    );

    /* Structs */
    struct Curator {
        uint256 amountStaked;
        uint256 subgraphShares;
    }
    struct IndexingNode {
        uint256 amountStaked;
        uint256 logoutStarted;
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
    mapping (address => mapping (bytes32 => Curator)) public curators;

    // Mapping subgraphId to list of addresses to Indexing Nodes
    mapping (address => mapping (bytes32 => IndexingNode)) public indexingNodes;

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
        minimumCurationStakingAmount = _minimumCurationStakingAmount;  // @imp c03
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
        minimumIndexingStakingAmount = _minimumIndexingStakingAmount;  // @imp i03
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
     * @dev Set the arbitrator address
     * @param _arbitrator <address> - The address of the arbitration contract or party
     */
    function setArbitrator (
        address _arbitrator
    )
        external
        onlyGovernance
        returns (bool success)
    {
        arbitrator = _arbitrator;
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
            // @imp c01 Handle internal call for Curation Staking
            stakeGraphTokensForCuration(_subgraphId, _from, _value);
        } else {
            // Slice the rest of the data as indexing records
            bytes memory _indexingRecords = _data.slice(33, _data.length-33);
            // Ensure that the remaining data is parse-able for indexing records
            require(_indexingRecords.length % 32 == 0);
            // @imp i01 Handle internal call for Index Staking
            stakeGraphTokensForIndexing(_subgraphId, _from, _value, _indexingRecords);
        }
        success = true;
    }

   /**
    * @dev Calculate number of shares that should be issued for the proportion
    *      of addedStake to totalStake based on a bonding curve
    * @param _addedStake <uint256> - Amount being added
    * @param _totalStake <uint256> - Amount total after added is created
    * @return issuedShares <uint256> - Amount of shares issued given the above
    */
    function stakeToShares (
        uint256 _addedStake,
        uint256 _totalStake
    )
        public
        pure
        returns (uint256 issuedShares)
    {
        issuedShares = _addedStake / _totalStake;
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
        require(
            curators[_staker][_subgraphId].amountStaked + _value
                    >= minimumCurationStakingAmount
        ); // @imp c02
        curators[_staker][_subgraphId].amountStaked += _value;
        subgraphs[_subgraphId].totalCurationStake += _value;
        curators[_staker][_subgraphId].subgraphShares +=
            stakeToShares(_value, subgraphs[_subgraphId].totalCurationStake);
        emit CurationNodeStaked(_staker, curators[_staker][_subgraphId].amountStaked);
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
        require(
            indexingNodes[_staker][_subgraphId].amountStaked + _value
                    >= minimumIndexingStakingAmount
        ); // @imp i02
        indexingNodes[_staker][_subgraphId].amountStaked += _value;
        subgraphs[_subgraphId].totalIndexingStake += _value;
        subgraphs[_subgraphId].totalIndexers += 1;
        emit IndexingNodeStaked(_staker, indexingNodes[_staker][_subgraphId].amountStaked);
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
        uint256 _value = indexingNodes[_staker][_subgraphId].amountStaked;
        require(_value > 0);
        delete indexingNodes[_staker][_subgraphId];
        subgraphs[_subgraphId].totalIndexingStake -= _value;
        subgraphs[_subgraphId].totalIndexers -= 1;
        token.burn(_value);
        emit IndexingNodeLogOut(_staker);
        success = true;
    }

    /**
     * @dev Indexing node can start logout process
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function beginLogout(bytes32 _subgraphId)
        public
    {
        require(indexingNodes[msg.sender][_subgraphId].amountStaked > 0);
        require(indexingNodes[msg.sender][_subgraphId].logoutStarted == 0);
        indexingNodes[msg.sender][_subgraphId].logoutStarted = block.timestamp;
        emit IndexingNodeLogOut(msg.sender);
    }

    /**
     * @dev Indexing node can finish the logout process after a cooling off period
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function finalizeLogout(bytes32 _subgraphId)
        public
    {
        require(
            indexingNodes[msg.sender][_subgraphId].logoutStarted + COOLING_PERIOD >= block.timestamp
        );
        uint256 _value = indexingNodes[msg.sender][_subgraphId].amountStaked;
        delete indexingNodes[msg.sender][_subgraphId];
        subgraphs[_subgraphId].totalIndexingStake -= _value;
        subgraphs[_subgraphId].totalIndexers -= 1;
        assert(token.transfer(msg.sender, _value));
    }
}
