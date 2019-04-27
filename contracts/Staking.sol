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
 * @req c08 Curation shares accrue 1 basis point per share of any fees an Indexing Node would
 *          earn when a channel settlement occurs for a given subgraphId.
 *
 * Indexer Requirements
 * @req i01 Any User can stake Graph Tokens to be included as an Indexer for a given subgraphId.
 * @req i02 The amount of tokens to stake required to become an Indexer must be greater than or
 *          equal to the minimum indexing staking amount.
 * @req i03 Only Governance can change the minimum indexing staking amount.
 * @req i04 An Indexer can start the process of removing their stake for a given subgraphId at
 *          any time.
 * @req i05 An Indexer may withdraw their stake for a given subgraphId after the process has
 *          been started and a thawing period has elapsed.
 * @req i06 An Indexer can add any amount of stake for a given subgraphId at any time, as long 
 *          as their total amount remains more than minimumIndexingStakingAmount.
 * @req i07 An Indexer earns a portion of all fees from the settlement a channel they were
 *          involved in.
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
 * @req f02 If the dispute is accepted by arbitration, the fisherman should receive a
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
import "./bancor/BancorFormula.sol";

contract Staking is Governed, TokenReceiver, BancorFormula
{
    using BytesLib for bytes;

    /* Events */
    event CurationNodeStaked (
        address indexed staker,
        uint256 amountStaked
    );

    event CurationNodeLogout (
        address indexed staker
    );

    event IndexingNodeStaked (
        address indexed staker,
        uint256 amountStaked
    );

    event IndexingNodeLogout (
        address indexed staker
    );

    // @dev Dispute was created by fisherman
    event DisputeCreated (
        bytes32 indexed _subgraphId,
        address indexed _indexingNode,
        address indexed _fisherman,
        bytes32 _disputeId,
        bytes _attestation
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
        uint256 subgraphShares; // In subgraph factory pattern, Subgraph Token Balance
    }

    struct IndexingNode {
        uint256 amountStaked;
        uint256 feesAccrued;
        uint256 logoutStarted;
    }

    struct Subgraph { // In subgraph factory pattern, these are just globals
        uint256 reserveRatio;
        uint256 totalCurationStake; // Reserve token
        uint256 totalCurationShares; // In subgraph factory pattern, Subgraph Token total supply
        uint256 totalIndexingStake;
        uint256 totalIndexers;
    }

    // @dev Store IPFS hash as 32 byte hash and 2 byte hash function
    struct IpfsHash {
        bytes32 hash; // Note: Not future proof against IPFS planned updates to
                      //       support multihash, which would require a len field
        uint16 hashFunction; // 0x1220 is 'Qm', or SHA256 with 32 byte length
    }

    // @dev signed message sent from Indexing Node in response to a request
    struct Attestation {
        // Content Identifier for request message sent from user to indexing node
        IpfsHash requestCID; // Note: Message is located at the given IPFS content addr
        // Content Identifier for signed response message from indexing node
        IpfsHash responseCID; // Note: Message is located at the given IPFS content addr
        // Amount of computational account units (gas) used to process query
        uint256 gasUsed;
        // Amount of data sent in the response
        uint256 responseNumBytes;
        // ECDSA vrs signature (using secp256k1)
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    uint256 private constant ATTESTATION_SIZE_BYTES = 197;

    // EIP-712 constants
    bytes32 private constant DOMAIN_TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant ATTESTATION_TYPE_HASH = keccak256(
            "Attestation(bytes32 subgraphId,IpfsHash requestCID,IpfsHash responseCID,uint256 gasUsed,uint256 responseNumBytes)IpfsHash(bytes32 hash,uint16 hashFunction)"
        );
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0.1");

    // TODO: EIP-1344 adds support for the Chain ID opcode
    //       Use that instead
    uint256 private constant CHAIN_ID = 1; // Mainnet

    // @dev Disputes contain info neccessary for the arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphId;
        address indexingNode;
        address fisherman;
        uint256 depositAmount;
    }

    /* ENUMS */
    enum TokenReceiptAction { Staking, Curation, Dispute, Settlement }

    /* STATE VARIABLES */
    // Minimum amount allowed to be staked by Market Curators
    uint256 public minimumCurationStakingAmount;

    // Default reserve ratio (for new subgraphs)
    // Note: A subgraph that hasn't been curated yet sets it's reserve ratio to
    //       this amount, which prevents changes from breaking the invariant. This
    //       means that we cannot control active curation markets, only new ones.
    // Note: In order to reset the reserveRatio of a subgraph to whatever this
    //       number is updated to, the market must sell and buy-back all of it's
    //       shares (taking advantage of the more attractive pricing). The trick
    //       is to set this number conservatively at first, and narrow in on the
    //       most optimal value, so that Curators are incentivized to perform this
    //       "upgrade" against their shares.
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public defaultReserveRatio;

    // Minimum amount allowed to be staked by Indexing Nodes
    uint256 public minimumIndexingStakingAmount;

    // Maximum number of Indexing Nodes staked higher than stake to consider 
    uint256 public maximumIndexers;

    // Percent of stake to slash in successful dispute
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercent;

    // Amount of seconds to wait until indexer can finish stake logout
    // @dev Thawing Period allows disputes to be processed during logout
    uint256 public thawingPeriod;

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

    /* MODIFIERS */
    // Disputes management only can be settled by arbitrator
    modifier onlyArbitrator {
        require(msg.sender == arbitrator);
        _;
    }

    /* CONSTANTS */
    // @dev 100% in parts per million.
    uint256 private constant MAX_PPM = 1000000;

    // @dev 1 basis point (0.01%) is 100 parts per million (PPM).
    uint256 private constant BASIS_PT = 100;

    /**
     * @dev Staking Contract Constructor
     * @param _governor <address> - Address of the multisig contract as Governor of this contract
     * @param _token <address> - Address of the Graph Protocol token
     */
    constructor (
        address _governor,
        uint256 _minimumCurationStakingAmount,
        uint256 _defaultReserveRatio,
        uint256 _minimumIndexingStakingAmount,
        uint256 _maximumIndexers,
        uint256 _slashingPercent,
        uint256 _thawingPeriod,
        address _token
    )
        public
        Governed(_governor)
    {
        // Governance Parameter Defaults
        minimumCurationStakingAmount = _minimumCurationStakingAmount;  // @imp c03
        defaultReserveRatio = _defaultReserveRatio;
        minimumIndexingStakingAmount = _minimumIndexingStakingAmount;  // @imp i03
        maximumIndexers = _maximumIndexers;
        slashingPercent = _slashingPercent;
        thawingPeriod = _thawingPeriod;
        arbitrator = governor;
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
     * @dev Set the percent that the default reserve ratio is for new subgraphs
     * @param _defaultReserveRatio <uint256> - Reserve ratio (in percent)
     */
    function updateDefaultReserveRatio (
        uint256 _defaultReserveRatio
    )
        external
        onlyGovernance
        returns (bool success)
    {
        // Reserve Ratio must be within 0% to 100% (exclusive)
        require(_defaultReserveRatio > 0);
        require(_defaultReserveRatio <= MAX_PPM);
        defaultReserveRatio = _defaultReserveRatio;
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
        // Slashing Percent must be within 0% to 100% (inclusive)
        require(_slashingPercent >= 0);
        require(_slashingPercent <= MAX_PPM);
        slashingPercent = _slashingPercent;
        return true;
    }

    /**
     * @dev Set the thawing period for indexer logout
     * @param _thawingPeriod <uint256> - Number of seconds for thawing period
     */
    function updateThawingPeriod (
        uint256 _thawingPeriod
    )
        external
        onlyGovernance
        returns (bool success)
    {
        thawingPeriod = _thawingPeriod;
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
        require(_data.length >= 1+32); // Must be at least 33 bytes (Header)
        TokenReceiptAction option = TokenReceiptAction(_data.slice(0, 1).toUint8(0));
        bytes32 _subgraphId = _data.slice(1, 32).toBytes32(0); // In subgraph factory, not necessary

        if (option == TokenReceiptAction.Staking) {
            // Slice the rest of the data as indexing records
            bytes memory _indexingRecords = _data.slice(33, _data.length-33);
            // Ensure that the remaining data is parse-able for indexing records
            require(_indexingRecords.length % 32 == 0);
            // @imp i01 Handle internal call for Index Staking
            stakeGraphTokensForIndexing(_subgraphId, _from, _value, _indexingRecords);
        } else
        if (option == TokenReceiptAction.Curation) {
            // @imp c01 Handle internal call for Curation Staking
            stakeGraphTokensForCuration(_subgraphId, _from, _value);
        } else
        if (option == TokenReceiptAction.Dispute) {
            require(_data.length == 33 + ATTESTATION_SIZE_BYTES);
            bytes memory _attestation = _data.slice(33, ATTESTATION_SIZE_BYTES);
            // Inner call to createDispute
            createDispute(_attestation, _subgraphId, _from, _value);
        } else
        if (option == TokenReceiptAction.Settlement) {
            require(_data.length >= 33 + 20); // Header + _indexingNode
            address _indexingNode = _data.slice(65, 20).toAddress(0);
            distributeChannelFees(_subgraphId, _indexingNode, _value);
        } else {
            revert();
        }
        success = true;
    }

    /**
     * @dev Calculate number of shares that should be issued in return for
     *      staking of _purchaseAmount of tokens, along the given bonding curve
     * @param _purchaseTokens <uint256> - Amount of tokens being staked (purchase amount)
     * @param _currentTokens <uint256> - Total amount of tokens currently in reserves
     * @param _currentShares <uint256> - Total amount of current shares issued
     * @param _reserveRatio <uint256> - Desired reserve ratio to maintain (in PPM)
     * @return issuedShares <uint256> - Amount of additional shares issued given the above
     */
    function stakeToShares (
        uint256 _purchaseTokens,
        uint256 _currentTokens,
        uint256 _currentShares,
        uint256 _reserveRatio
    )
        public
        view
        returns (uint256 issuedShares)
    {
        issuedShares = calculatePurchaseReturn(_currentShares,
                                               _currentTokens,
                                               uint32(_reserveRatio),
                                               _purchaseTokens);
    }

    /**
     * @dev Calculate number of tokens that should be returned for the proportion
     *      of _returnedShares to _currentShares, along the given bonding curve
     * @param _returnedShares <uint256> - Amount of shares being returned
     * @param _currentTokens <uint256> - Total amount of tokens currently in reserves
     * @param _currentShares <uint256> - Total amount of current shares issued
     * @param _reserveRatio <uint256> - Desired reserve ratio to maintain (in PPM)
     * @return refundTokens <uint256> - Amount of tokens to return given the above
     */
    function sharesToStake (
        uint256 _returnedShares,
        uint256 _currentTokens,
        uint256 _currentShares,
        uint256 _reserveRatio
    )
        public
        view
        returns (uint256 refundTokens)
    {
        refundTokens = calculateSaleReturn(_currentShares,
                                           _currentTokens,
                                           uint32(_reserveRatio),
                                           _returnedShares);
    }

    /**
     * @dev Stake Graph Tokens for Market Curation by subgraphId
     * @param _subgraphId <bytes32> - Subgraph ID the Curator is staking Graph Tokens for
     * @param _curator <address> - Address of Staking party
     * @param _tokenAmount <uint256> - Amount of Graph Tokens to be staked
     */
    function stakeGraphTokensForCuration (
        bytes32 _subgraphId,
        address _curator,
        uint256 _tokenAmount
    )
        private
    {
        // Overflow protection
        require(subgraphs[_subgraphId].totalCurationStake + _tokenAmount
                > subgraphs[_subgraphId].totalCurationStake);

        // If this subgraph hasn't been curated before...
        // NOTE: We have to do this to initialize the curve or else it has
        //       a discontinuity and cannot be computed. This method ensures
        //       that this doesn't occur, and also sets the initial slope for
        //       the curve (controlled by minimumCurationStake)
        if (subgraphs[_subgraphId].totalCurationStake == 0) {

            // Additional pre-condition check
            require(_tokenAmount >= minimumCurationStakingAmount);

            // (Re)set the default reserve ratio to whatever governance has set
            subgraphs[_subgraphId].reserveRatio = defaultReserveRatio;

            // The first share costs minimumCurationStake amount of tokens
            curators[_curator][_subgraphId].subgraphShares = 1;
            subgraphs[_subgraphId].totalCurationShares = 1;
            curators[_curator][_subgraphId].amountStaked = minimumCurationStakingAmount;
            subgraphs[_subgraphId].totalCurationStake = minimumCurationStakingAmount;
            _tokenAmount -= minimumCurationStakingAmount;
        }

        if (_tokenAmount > 0) { // Corner case if only minimum is staked on first stake
            // Obtain the amount of shares to buy with the amount of tokens to sell
            // according to the bonding curve
            uint256 _newShares =
                    stakeToShares(_tokenAmount,
                                  subgraphs[_subgraphId].totalCurationStake,
                                  subgraphs[_subgraphId].totalCurationShares,
                                  subgraphs[_subgraphId].reserveRatio);

            // Update the amount of tokens _curator has, and overall amount staked
            curators[_curator][_subgraphId].amountStaked += _tokenAmount;
            subgraphs[_subgraphId].totalCurationStake += _tokenAmount;

            // @imp c02 Ensure the minimum amount is staked
            // TODO Validate the need for this requirement
            require(curators[_curator][_subgraphId].amountStaked
                    >= minimumCurationStakingAmount);

            // Update the amount of shares issued to _curator, and total amount issued
            curators[_curator][_subgraphId].subgraphShares += _newShares;
            subgraphs[_subgraphId].totalCurationShares += _newShares;

            // Ensure curators cannot stake more than 100% in basis points
            // Note: ensures that distributeChannelFees() does not revert
            require(subgraphs[_subgraphId].totalCurationShares
                    <= (MAX_PPM / BASIS_PT));
        }

        // Emit the CurationNodeStaked event (updating the running tally)
        emit CurationNodeStaked(_curator, curators[_curator][_subgraphId].amountStaked);
    }

    /**
     * @dev Return any amount of shares to get tokens back (above the minimum)
     * @param _subgraphId <bytes32> - Subgraph ID the Curator is returning shares for
     * @param _numShares <uint256> - Amount of shares to return
     */
    function curatorLogout (
        bytes32 _subgraphId,
        uint256 _numShares
    )
        external
    {
        // Underflow protection
        require(curators[msg.sender][_subgraphId].subgraphShares >= _numShares);

        // Obtain the amount of tokens to refunded with the amount of shares returned
        // according to the bonding curve
        uint256 _tokenRefund = sharesToStake(_numShares,
                                             subgraphs[_subgraphId].totalCurationStake,
                                             subgraphs[_subgraphId].totalCurationShares,
                                             subgraphs[_subgraphId].reserveRatio);

        // Underflow protection
        require(curators[msg.sender][_subgraphId].amountStaked >= _tokenRefund);

        // Keep track of whether this is a full logout
        bool fullLogout = (curators[msg.sender][_subgraphId].amountStaked == _tokenRefund);

        // Update the amount of tokens Curator has, and overall amount staked
        curators[msg.sender][_subgraphId].amountStaked -= _tokenRefund;
        subgraphs[_subgraphId].totalCurationStake -= _tokenRefund;

        // Update the amount of shares Curator has, and overall amount of shares
        curators[msg.sender][_subgraphId].subgraphShares -= _numShares;
        subgraphs[_subgraphId].totalCurationShares -= _numShares;

        if (fullLogout) {
            // Emit the CurationNodeLogout event
            emit CurationNodeLogout(msg.sender);
        } else {
            // Require that if not fully logging out, at least the minimum is kept staked
            // TODO Validate the need for this requirement
            require(curators[msg.sender][_subgraphId].amountStaked
                        >= minimumCurationStakingAmount);

            // Emit the CurationNodeStaked event (updating the running tally)
            emit CurationNodeStaked(msg.sender, curators[msg.sender][_subgraphId].amountStaked);
        }
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
        require(indexingNodes[_indexer][_subgraphId].amountStaked + _value
                    >= minimumIndexingStakingAmount); // @imp i02
        if (indexingNodes[_indexer][_subgraphId].amountStaked == 0)
            subgraphs[_subgraphId].totalIndexers += 1; // has not staked before
        indexingNodes[_indexer][_subgraphId].amountStaked += _value;
        subgraphs[_subgraphId].totalIndexingStake += _value;
        emit IndexingNodeStaked(_indexer, indexingNodes[_indexer][_subgraphId].amountStaked);
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
        emit IndexingNodeLogout(msg.sender);
    }

    /**
     * @dev Indexing node can finish the logout process after a thawing off period
     * @param _subgraphId <bytes32> - Subgraph ID the Indexing Node has staked Graph Tokens for
     */
    function finalizeLogout(bytes32 _subgraphId)
        external
    {
        require(indexingNodes[msg.sender][_subgraphId].logoutStarted + thawingPeriod
                    <= block.timestamp);
        // Return the amount the Indexing Node has staked
        uint256 _stake = indexingNodes[msg.sender][_subgraphId].amountStaked;
        // Return any outstanding fees accrued the Indexing Node does not have yet
        uint256 _fees = indexingNodes[msg.sender][_subgraphId].feesAccrued;
        delete indexingNodes[msg.sender][_subgraphId]; // Re-entrancy protection
        // Decrement the total amount staked by the amount being returned
        subgraphs[_subgraphId].totalIndexingStake -= _stake;
        subgraphs[_subgraphId].totalIndexers -= 1;
        // Send them all their funds back
        assert(token.transfer(msg.sender, _stake + _fees));
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
        return slashingPercent * _value / MAX_PPM; // slashingPercent is in PPM
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
        bytes memory _attestation,
        bytes32 _subgraphId,
        address _fisherman,
        uint256 _amount
    )
        private
    {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        bytes32 _disputeId = keccak256(abi.encode(
                // HACK: Remove this line until eth_signTypedData is in common use
                //"\x19\x01", // EIP-191 encoding pad, EIP-712 version 1
                "\x19Ethereum Signed Message:\n", 64, // 64 bytes (2 hashes)
                // END HACK
                keccak256(abi.encode( // EIP 712 domain separator
                        DOMAIN_TYPE_HASH,
                        DOMAIN_NAME_HASH,
                        DOMAIN_VERSION_HASH,
                        CHAIN_ID, // (Change to block.chain_id after EIP-1344 support)
                        this, // contract address
                        // Application-specific domain separator
                        // Ensures msgs for different subgraphs cannot be reused
                        // Note: Not necessary when subgraphs are factory pattern because of contract address
                        _subgraphId // EIP-712 Salt
                    )),
                keccak256(abi.encode( // EIP 712-encoded message hash
                        ATTESTATION_TYPE_HASH,
                        _attestation.slice(0, ATTESTATION_SIZE_BYTES-65) // Everything except the signature
                    ))
            ));

        // Decode the signature
        (uint8 v, bytes32 r, bytes32 s) = abi.decode( // VRS signature components
                _attestation.slice(ATTESTATION_SIZE_BYTES-65, 65), // just the signature
                (uint8, bytes32, bytes32) // V, R, and S
            );

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // Note: The signer of the attestation is the indexing node that served it
        address _indexingNode = ecrecover(_disputeId, v, r, s);

        // Get amount _indexingNode has staked (amountStaked is member 0)
        uint256 _stake = indexingNodes[_indexingNode][_subgraphId].amountStaked;
        require(_stake > 0); // This also validates that _indexingNode exists

        // Ensure that fisherman has posted at least that amount
        require(_amount >= getRewardForValue(_stake));
        // NOTE: There is a potential for a front-running attack against a fisherman
        //       by the indexing node if this were strictly equal to the amount of
        //       reward that the fisherman were to expect. As a partial mitigation for
        //       this, the fisherman can over-stake their bond. For every X amount that
        //       the fisherman overstakes by, the staker would have to also up their
        //       stake by the same proportion, and due to the reward being slasingPercent
        //       of the total stake already, the amount the indexing node would have to
        //       up their stake by would be a significant multiple of this increase.
        //
        //       As an example, if slashingPercent were 10%, and the indexer had staked
        //       100 tokens, the minimum the fisherman would be required to stake is 10
        //       tokens. If the fisherman staked 20 tokens instead on their dispute, the
        //       indexing node would have to stake more than 100 tokens extra to front-
        //       run their dispute and cancel it before it is created. This is a safety
        //       factor of 10x for the fisherman. The smaller slashingPercent is, the
        //       larger the multiple would be.
        //
        //       Due to this mechanic, this partial mitigation may be enough to defend
        //       against this in practice until a better design is contructed that takes
        //       this into account.

        // A fisherman can only open one dispute with a given indexing node
        // per subgraphId at a time
        require(disputes[_disputeId].fisherman == address(0)); // Must be empty

        // Store dispute
        disputes[_disputeId] =
                Dispute(_subgraphId, _indexingNode, _fisherman, _amount);

        // Log event that new dispute was created against _indexingNode
        emit DisputeCreated(_subgraphId, _indexingNode, _fisherman, _disputeId, _attestation);
    }

    /**
     * @dev The arbitrator can verify a dispute as being valid.
     * @param _disputeId <bytes32> - ID of the dispute to be verified
     */
    function verifyDispute (
        bytes32 _disputeId
    )
        external
        onlyArbitrator
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _bond = disputes[_disputeId].depositAmount;
        require(_bond > 0); // Ensure this is a valid dispute
        address _fisherman = disputes[_disputeId].fisherman;
        address _indexer = disputes[_disputeId].indexingNode;
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        delete disputes[_disputeId]; // Re-entrancy protection

        // Have staking slash the index node and reward the fisherman
        // Give the fisherman a reward equal to the slashingPercent of the indexer's stake
        uint256 _stake = indexingNodes[_indexer][_subgraphId].amountStaked;
        assert(_stake > 0); // Ensure this is a valid staker (should always be true)
        uint256 _reward = getRewardForValue(_stake);
        assert(_reward <= _stake); // sanity check on fixed-point math
        // Capture the fees that the indexer would've earned
        uint256 _fees = indexingNodes[_indexer][_subgraphId].feesAccrued;
        delete indexingNodes[_indexer][_subgraphId]; // Re-entrancy protection

        // Remove Indexing Node from Subgraph's stakers
        subgraphs[_subgraphId].totalIndexingStake -= _stake;
        subgraphs[_subgraphId].totalIndexers -= 1;
        emit IndexingNodeLogout(_indexer);

        // Give governance the difference between the fisherman's reward and the total stake
        // plus the Indexing Node's accrued fees
        token.transfer(governor, (_stake - _reward) + _fees); // TODO Burn or give to governance?

        // Give the fisherman their reward and bond back
        token.transfer(_fisherman, _reward + _bond);

        // Log event that we awarded _fisherman _reward in resolving _disputeId
        emit DisputeAccepted(_disputeId, _subgraphId, _indexer, _reward);
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid.
     * @param _disputeId <bytes32> - ID of the dispute to be rejected
     */
    function rejectDispute (
        bytes32 _disputeId
    )
        external
        onlyArbitrator
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _bond = disputes[_disputeId].depositAmount;
        require(_bond > 0); // Ensure this is a valid dispute
        address _fisherman = disputes[_disputeId].fisherman;
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        delete disputes[_disputeId]; // Re-entrancy protection

        // Slash the fisherman's bond and send to the governor
        token.transfer(governor, _bond); // TODO Burn or give to governance?

        // Log event that we slashed _fisherman for _bond in resolving _disputeId
        emit DisputeRejected(_disputeId, _subgraphId, _fisherman, _bond);
    }

    /**
     * @dev Distribute the channel fees to the given Indexing Node and all the Curators
     *      for that subgraph. Curator fees are applied through reserve balance increase
     *      so every Curator logout will earn back more coins back per share, and shares
     *      cost more to buy.
     * @param _subgraphId <bytes32> - Subgraph that the fees were accrued for.
     * @param _indexingNode <address> - Indexing Node that earned the fees.
     * @param _feesEarned <uint256> - Total amount of fees earned.
     */
    function distributeChannelFees (
        bytes32 _subgraphId,
        address _indexingNode,
        uint256 _feesEarned
    )
        private
    {
        // Each share minted gives basis point (0.01%) of the fee collected in that subgraph.
        uint256 _curatorRewardBasisPts =
                subgraphs[_subgraphId].totalCurationShares * BASIS_PT;
        assert(_curatorRewardBasisPts < MAX_PPM); // should be less than 100%
        uint256 _curatorPortion = (_curatorRewardBasisPts * _feesEarned) / MAX_PPM;
        // Give the indexing node their part of the fees
        indexingNodes[msg.sender][_subgraphId].feesAccrued += (_feesEarned - _curatorPortion);
        // Increase the token balance for the subgraph (each share gets more tokens when sold)
        subgraphs[_subgraphId].totalCurationStake += _curatorPortion;
    }

    /**
     * @dev The Indexing Node can get all of their accrued fees for a subgraph at once.
     *      Indexing Node would be able to log out all the fees they earned during a dispute.
     * @param _subgraphId <bytes32> - Subgraph the Indexing Node wishes to withdraw for.
     */
    function withdrawFees (
        bytes32 _subgraphId
    )
        external
    {
        uint256 _feesAccrued = indexingNodes[msg.sender][_subgraphId].feesAccrued;
        require(_feesAccrued > 0);
        indexingNodes[msg.sender][_subgraphId].feesAccrued = 0; // Re-entrancy protection
        token.transfer(msg.sender, _feesAccrued);
    }
}
