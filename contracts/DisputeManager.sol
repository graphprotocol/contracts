pragma solidity ^0.5.2;

/*
 * @title Dispute Resolution Manager contract
 *
 * @author Bryant Eisenbach
 * @author Reuven Etzion
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
 */

import "./Governed.sol";
import "./Staking.sol";
import "./GraphToken.sol";

contract DisputeManager is Governed
{
    /* Events */
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
    // @dev Staking contract address (set only at runtime)
    Staking staking;

    // @dev Graph Token address
    GraphToken token;

    // @dev Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes32 => Dispute) private disputes;

    /* Modifiers */
    // Only the designated arbitrator has access (Governance in v1 of Graph Protocol)
    modifier onlyArbitrator () {
        require(msg.sender == governor);
        _;
    }

    /**
     * @param _staking <address> - Address of the staking contract
     * @param _token <address> - Address of the Graph Token contract
     * @param _governor <address> - Address of the multisig contract as Governor of
     *                              this contract
     */
    constructor (
        address _staking,
        address _token,
        address _governor
    )
        public
        Governed(_governor)
    {
        staking = Staking(_staking);
        token = GraphToken(_token);
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
        (uint256 _stake, uint256 _logoutStarted) =
                staking.indexingNodes(_indexingNode, _subgraphId);
        require(_stake > 0); // This also validates that _indexingNode exists

        // Ensure that fisherman has posted at least that amount
        require(_amount >= staking.getRewardForValue(_stake));

        // A fisherman can only open one dispute with a given indexing node
        // per subgraphId at a time
        bytes32 _disputeId =
                keccak256(abi.encode(_fisherman, _indexingNode, _subgraphId));
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
        onlyArbitrator
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _amount = disputes[_disputeId].depositAmount;
        require(_amount > 0);
        address _fisherman = disputes[_disputeId].fisherman;
        require(_fisherman != address(0));
        address _indexingNode = disputes[_disputeId].indexingNode;
        require(_indexingNode != address(0));
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        require(_subgraphId != bytes32(0));

        // Have staking slash the index node and reward the fisherman
        staking.slashStake(_subgraphId, _indexingNode, _fisherman);

        // Give the fisherman their bond back
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
        onlyArbitrator
        returns (bool success)
    {
        // Input validation, read storage for later (when deleted)
        uint256 _amount = disputes[_disputeId].depositAmount;
        require(_amount > 0);
        address _fisherman = disputes[_disputeId].fisherman;
        require(_fisherman != address(0));
        bytes32 _subgraphId = disputes[_disputeId].subgraphId;
        require(_subgraphId != bytes32(0));

        // Slash the fisherman's bond
        delete disputes[_disputeId];
        token.transfer(governor, _amount);

        emit DisputeRejected(_disputeId, _subgraphId, _fisherman, _amount);
    }
}
