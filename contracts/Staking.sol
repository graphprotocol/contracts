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
 * @req c05 A Curator can add any amount of stake for a given subgraphId at any time, as long 
 *          as their total amount remains more than minimumCurationStakingAmount.
 * @req c06 A Curator can remove any amount of their stake for a given subgraphId at any time, 
 *          as long as their total amount remains more than minimumCurationStakingAmount.
 * @req c07 A Curator can remove all of their stake for a given subgraphId at any time.
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
 * @req i06 An Indexer can add any amount of stake for a given subgraphId at any time, as long 
 *          as their total amount remains more than minimumIndexingStakingAmount.
 *
 * Slashing Requirements
 * @req s01 The Dispute Manager contract can burn the staked Tokens of any Indexer.
 * @req s02 Only Governance can change the Dispute Manager contract address.
 * @reg s03 Only Governance can update slashingPercent.
 *
 * Fisherman Requirements
 * @req f01 A fisherman can provide a bond, a valid read request and an invalid read
 *          response which has been signed by a current indexing node to create a
 *          dispute.
 * @req f02 If the dispute is validated by arbitration, the fisherman should receive a
 *          reward proportional to the amount staked by the indexing node.
 *
 * Dispute Arbitrator Requirements
 * @req a01 The arbitrator can rule to accept a proposed dispute, which will trigger a
 *          slashing of the indexing node that the dispute concerns.
 * @req a02 The arbitrator can rule to reject a proposed dispute, which will slash the
 *          bond posted by the fisherman who proposed it.
 *
 * @notice Dispute resolution is handled through an on-chain dispute resolution
 *         process. In the v1 specification the outcome of a dispute will be decided
 *         by a centralized arbitrator (the contract owner / multisig contract)
 *         interacting with the on-chain dispute resolution process.
 *
 * ----------------------------------- TODO This may change -------------------------------------
 * @notice Indexing Nodes who have staked for a dataset, are not limited by the protocol in how
 *         many read requests they may process for that dataset. However, it may be assumed that
 *         Indexing Nodes with higher deposits will receive more read requests and thus collect
 *         more fees, all else being equal, as this represents a greater economic security margin
 *         to the end user.
 *
 */

import "./GraphToken.sol";
import "./Governed.sol";
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

    // @dev Dispute was created by fisherman
    event DisputeCreated (
        bytes32 indexed _subgraphId,
        address indexed _indexingNode,
        address indexed _fisherman,
        bytes32 _disputeId
    );

    // @dev Dispute was accepted, indexing node lost their stake
    event DisputeAccepted (
        bytes32 indexed _disputeId,
        bytes32 indexed _subgraphId,
        address indexed _indexingNode,
        uint256 _amount
    );

    // @dev Dispute was rejected, fisherman lost the given bond amount
    event DisputeRejected (
        bytes32 indexed _disputeId,
        bytes32 indexed _subgraphId,
        address indexed _fisherman,
        uint256 _amount
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

    // @dev Store 34 byte IPFS hash as 32 bytes
    struct IpfsHash {
        bytes hash;
        uint8 hashFunction;
    }

    // @dev signed message sent from Indexing Node in response to a request
    struct Attestation {
        IpfsHash requestCID;
        IpfsHash responseCID;
        uint256 gasUsed;
        uint256 responseNumBytes;
        // ECDSA vrs signature (using secp256k1)
        uint256 v;
        bytes32 r;
        bytes32 s;
    }

    // @dev Disputes contain info neccessary for the arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphId;
        address indexingNode;
        address fisherman;
        uint256 depositAmount;
    }

    /* STATE VARIABLES */
    // Minimum amount allowed to be staked by Market Curators
    uint256 public minimumCurationStakingAmount;

    // Minimum amount allowed to be staked by Indexing Nodes
    uint256 public minimumIndexingStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider 
    uint256 public maximumIndexers;

    // Percent of stake to slash in successful dispute
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercent;

    // Mapping subgraphId to list of addresses to Curators
    mapping (address => mapping (bytes32 => Curator)) public curators;

    // Mapping subgraphId to list of addresses to Indexing Nodes
    mapping (address => mapping (bytes32 => IndexingNode)) public indexingNodes;

    // Subgraphs mapping
    mapping (bytes32 => Subgraph) public subgraphs;

    // @dev Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes32 => Dispute) private disputes;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Graph Token address
    GraphToken public token;

    /* CONSTANTS */
    uint constant COOLING_PERIOD = 7 days;

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     * @param _token <address> - Address of the Graph Protocol token
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
     * @dev Set the percent that the fisherman gets when slashing occurs
     * @param _slashingPercent <uint256> - Slashing percent
     */
    function updateSlashingPercentage (
        uint256 _slashingPercent
    )
        external
        onlyGovernance
        returns (bool success)
    {
        slashingPercent = _slashingPercent;
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
    function tokensReceived (
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
        uint8 option = _data.slice(0, 1).toUint8(0);
        bytes32 _subgraphId = _data.slice(1, 32).toBytes32(0);

        if (option == 1) {
            // @imp c01 Handle internal call for Curation Staking
            stakeGraphTokensForCuration(_subgraphId, _from, _value);
        } else if (option == 0) {
            // Slice the rest of the data as indexing records
            bytes memory _indexingRecords = _data.slice(33, _data.length-33);
            // Ensure that the remaining data is parse-able for indexing records
            require(_indexingRecords.length % 32 == 0);
            // @imp i01 Handle internal call for Index Staking
            stakeGraphTokensForIndexing(_subgraphId, _from, _value, _indexingRecords);
        } else if (option == 2) {
            require(_data.length == 33 + 269); // Attestation is 269 bytes
            // Convert to the Attestation struct (manually)
            Attestation memory _attestation;
            _attestation.requestCID.hash = _data.slice(33, 32);
            _attestation.requestCID.hashFunction = _data.slice(65, 1).toUint8(0);
            _attestation.responseCID.hash = _data.slice(66, 32);
            _attestation.responseCID.hashFunction = _data.slice(98, 1).toUint8(0);
            _attestation.gasUsed = _data.slice(99, 32).toUint(0);
            _attestation.responseNumBytes = _data.slice(131, 32).toUint(0);
            _attestation.v = _data.slice(163, 32).toUint(0);
            _attestation.r = _data.slice(195, 32).toBytes32(0);
            _attestation.s = _data.slice(237, 32).toBytes32(0);
            // Inner call to createDispute
            createDispute(_attestation, _subgraphId, _from, _value);
        } else {
            revert();
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
     * @param _curator <address> - Address of Staking party
     * @param _amount <uint256> - Amount of Graph Tokens to be staked
     */
    function stakeGraphTokensForCuration (
        bytes32 _subgraphId,
        address _curator,
        uint256 _amount
    )
        private
    {
        require(
            curators[_curator][_subgraphId].amountStaked + _amount
                    >= minimumCurationStakingAmount
        ); // @imp c02
        curators[_curator][_subgraphId].amountStaked += _amount;
        subgraphs[_subgraphId].totalCurationStake += _amount;
        curators[_curator][_subgraphId].subgraphShares +=
            stakeToShares(_amount, subgraphs[_subgraphId].totalCurationStake);
        emit CurationNodeStaked(_curator, curators[_curator][_subgraphId].amountStaked);
    }

    /**
     * @dev Stake Graph Tokens for Indexing Node data retrieval by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node is staking Graph Tokens for
     * @param _indexer <address> - Address of Staking party
     * @param _value <uint256> - Amount of Graph Tokens to be staked
     * @param _indexingRecords <bytes> - Index Records of the indexes being stored
     */
    function stakeGraphTokensForIndexing (
        bytes32 _subgraphId,
        address _indexer,
        uint256 _value,
        bytes memory _indexingRecords
    )
        private
    {
        require(indexingNodes[msg.sender][_subgraphId].logoutStarted == 0);
        require(
            indexingNodes[_indexer][_subgraphId].amountStaked + _value
                    >= minimumIndexingStakingAmount
        ); // @imp i02
        if (indexingNodes[_indexer][_subgraphId].amountStaked == 0)
            subgraphs[_subgraphId].totalIndexers += 1; // has not staked before
        indexingNodes[_indexer][_subgraphId].amountStaked += _value;
        subgraphs[_subgraphId].totalIndexingStake += _value;
        emit IndexingNodeStaked(_indexer, indexingNodes[_indexer][_subgraphId].amountStaked);
    }

    /**
     * @dev Get the amount of fisherman reward for a given amount of stake
     * @param _value <uint256> - Amount of validator's stake
     * @return <uint256> - Percentage of validator's stake to be considered a reward
     */
    function getRewardForValue(
        uint256 _value
    )
        public
        view
        returns (uint256)
    {
        return slashingPercent * _value / 1000000; // slashingPercent is in PPM
    }


    /**
     * @dev Arbitrator contract can slash staked Graph Tokens in dispute
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     * @param _indexer <address> - Address of Staking party that is being slashed
     * @param _fisherman <address> - Address of Fisherman party to be rewarded
     */
    function slashStake (
        bytes32 _subgraphId,
        address _indexer,
        address _fisherman
    )
        private
    {
        uint256 _value = indexingNodes[_indexer][_subgraphId].amountStaked;
        require(_value > 0);
        delete indexingNodes[_indexer][_subgraphId];
        subgraphs[_subgraphId].totalIndexingStake -= _value;
        subgraphs[_subgraphId].totalIndexers -= 1;
        // Give the fisherman a reward equal to the slashingPercent of the indexer's stake
        uint256 _reward = getRewardForValue(_value);
        assert(_reward <= _value); // sanity check on fixed-point math
        token.transfer(governor, _value - _reward);
        token.transfer(_fisherman, _reward);
        emit IndexingNodeLogOut(_indexer);
    }

    /**
     * @dev Indexing node can start logout process
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function beginLogout(bytes32 _subgraphId)
        external
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
        external
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

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _attestation <Attestation> - Signed Attestation message
     * @param _subgraphId <bytes32> - SubgraphId that Attestation message
     *                                contains (in request raw object at CID)
     * @param _fisherman <address> - Creator of dispute
     * @param _amount <uint256> - Amount of tokens staked
     * @notice Payable using Graph Tokens for deposit
     */
    function createDispute (
        Attestation memory _attestation,
        bytes32 _subgraphId,
        address _fisherman,
        uint256 _amount
    )
        private
    {
        // The signer of the attestation is the indexing node that served it
        bytes memory _rawAttestation = abi.encode(
                    _attestation.requestCID.hash,
                    _attestation.requestCID.hashFunction,
                    _attestation.responseCID.hash,
                    _attestation.responseCID.hashFunction,
                    _attestation.gasUsed,
                    _attestation.responseNumBytes
                );
        address _indexingNode = ecrecover(
                    keccak256(_rawAttestation), // Unsigned Message
                    uint8(_attestation.v), _attestation.r, _attestation.s
                );

        // Get amount _indexingNode has staked (amountStaked is member 0)
        uint256 _stake = indexingNodes[_indexingNode][_subgraphId].amountStaked;
        require(_stake > 0); // This also validates that _indexingNode exists

        // Ensure that fisherman has posted at least that amount
        require(_amount >= getRewardForValue(_stake));

        // A fisherman can only open one dispute with a given indexing node
        // per subgraphId at a time
        bytes32 _disputeId = keccak256(abi.encode(_rawAttestation, _subgraphId));
        require(disputes[_disputeId].fisherman == address(0)); // Must be empty

        disputes[_disputeId] = Dispute(
            _subgraphId,
            _indexingNode,
            _fisherman,
            _amount
        );
        emit DisputeCreated(
            _subgraphId,
            _indexingNode,
            _fisherman,
            _disputeId
        );
    }

    /**
     * @dev The arbitrator can verify a dispute as being valid.
     * @param _disputeId <bytes32> - ID of the dispute to be verified
     */
    function verifyDispute (
        bytes32 _disputeId
    )
        external
        onlyGovernance
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _amount = disputes[_disputeId].depositAmount;
        address _fisherman = disputes[_disputeId].fisherman;
        address _indexingNode = disputes[_disputeId].indexingNode;
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        require(_amount > 0); // Check if this is a valid dispute

        // Have staking slash the index node and reward the fisherman
        slashStake(_subgraphId, _indexingNode, _fisherman);

        // Give the fisherman their bond back too
        delete disputes[_disputeId];
        token.transfer(_fisherman, _amount);

        emit DisputeAccepted(_disputeId, _subgraphId, _indexingNode, _amount);
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid.
     * @param _disputeId <bytes32> - ID of the dispute to be rejected
     */
    function rejectDispute (
        bytes32 _disputeId
    )
        external
        onlyGovernance
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _amount = disputes[_disputeId].depositAmount;
        address _fisherman = disputes[_disputeId].fisherman;
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        require(_amount > 0); // Check if this is a valid dispute

        // Slash the fisherman's bond and send to the governer
        delete disputes[_disputeId];
        token.transfer(governor, _amount);

        emit DisputeRejected(_disputeId, _subgraphId, _fisherman, _amount);
    }
}
