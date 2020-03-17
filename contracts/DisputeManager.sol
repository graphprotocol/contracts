pragma solidity ^0.5.2;

/*
 * @title DisputeManager contract
 *
 * Provides an effective way to align the incentives of the multiple participants ensuring that Query Results are trustful.
 */

import "./Governed.sol";
import "./GraphToken.sol";
import "./Staking.sol";
import "./bytes/BytesLib.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract DisputeManager is Governed {
    using BytesLib for bytes;
    using ECDSA for bytes32;
    using SafeMath for uint256;

    // @dev Disputes contain info neccessary for the arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphID;
        address indexNode;
        address fisherman;
        uint256 depositAmount;
    }

    // -- Attestation --

    // @dev Store IPFS hash as 32 byte hash and 2 byte hash function
    struct IpfsHash {
        // Note: Not future proof against IPFS planned updates to support multihash, which would require a len field
        bytes32 hash;
        // 0x1220 is 'Qm', or SHA256 with 32 byte length
        uint16 hashFunction;
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

    uint256 private constant ATTESTATION_SIZE_BYTES = 192;
    uint256 private constant SIGNATURE_SIZE_BYTES = 65;

    // -- EIP-712  --

    bytes32 private constant DOMAIN_TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant DOMAIN_NAME_HASH = keccak256(
        bytes("Graph Protocol")
    );
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256(bytes("0.1"));
    bytes32 private constant ATTESTATION_TYPE_HASH = keccak256(
        "Attestation(IpfsHash requestCID,IpfsHash responseCID,uint256 gasUsed,uint256 responseNumBytes)IpfsHash(bytes32 hash,uint16 hashFunction)"
    );
    uint256 private constant CHAIN_ID = 1; // 1 - mainnet // TODO: EIP-1344 adds support for the Chain ID opcode
    bytes32 private DOMAIN_SEPARATOR;

    // @dev 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // @dev 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // @dev Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeID - Hash of readIndex data + disputer data
    mapping(bytes32 => Dispute) public disputes;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Percent of stake to slash in successful dispute
    // @dev Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercent;

    // Graph Token address
    GraphToken public token;

    // Staking contract used for slashing
    Staking public staking;

    // -- Events --

    event DisputeCreated(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        bytes attestation
    );

    event DisputeAccepted(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        uint256 amount
    );

    event DisputeRejected(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        uint256 amount
    );

    event DisputeIgnored(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        uint256 amount
    );

    modifier onlyArbitrator {
        require(msg.sender == arbitrator, "Caller is not the Arbitrator");
        _;
    }

    /**
     * @dev DisputeManager Contract Constructor
     * @param _governor <address> - Owner address of this contract
     * @param _token <address> - Address of the Graph Protocol token
     * @param _arbitrator <address> - Arbitrator role
     * @param _staking <address> - Address of the staking contract used for slashing
     * @param _slashingPercent <uint256> - Percent of stake the fisherman gets on slashing (in PPM)
     */
    constructor(
        address _governor,
        address _token,
        address _arbitrator,
        address _staking,
        uint256 _slashingPercent
    ) public Governed(_governor) {
        arbitrator = _arbitrator;
        token = GraphToken(_token);
        staking = Staking(_staking);

        slashingPercent = _slashingPercent;

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME_HASH,
                DOMAIN_VERSION_HASH,
                CHAIN_ID,
                address(this)
            )
        );
    }

    /**
     * @dev Return whether a dispute exists or not
     * @param _disputeID <bool> - True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeID) public view returns (bool) {
        return disputes[_disputeID].fisherman != address(0);
    }

    /**
     * @dev Get the amount of fisherman reward for a given amount of stake
     * @param _value <uint256> - Amount of validator's stake
     * @return <uint256> - Percentage of validator's stake to be considered a reward
     */
    function getRewardForStake(uint256 _value) public view returns (uint256) {
        return slashingPercent.mul(_value).div(MAX_PPM); // slashingPercent is in PPM
    }

    /**
     * @dev Get the hash of encoded message to use as disputeID
     * @param _attestation <Attestation> - Signed Attestation message
     * @return <bytes32> - Hash of encoded message used as disputeID
     */
    function getDisputeID(bytes memory _attestation)
        public
        view
        returns (bytes32)
    {
        // TODO: add a nonce?
        return
            keccak256(
                abi.encodePacked(
                    // HACK: Remove this line until eth_signTypedData is in common use
                    // "\x19\x01", // EIP-191 encoding pad, EIP-712 version 1
                    "\x19Ethereum Signed Message:\n64",
                    // END HACK
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(ATTESTATION_TYPE_HASH, _attestation) // EIP 712-encoded message hash
                    )
                )
            );
    }

    /**
     * @dev Set the percent that the fisherman gets when slashing occurs
     * @param _slashingPercent <uint256> - Slashing percent
     */
    function setSlashingPercent(uint256 _slashingPercent)
        external
        onlyGovernance
    {
        // Slashing Percent must be within 0% to 100% (inclusive)
        require(
            _slashingPercent >= 0,
            "Slashing percent must above or equal to 0"
        );
        require(
            _slashingPercent <= MAX_PPM,
            "Slashing percent must be below or equal to MAX_PPM"
        );

        slashingPercent = _slashingPercent;
    }

    /**
     * @dev Set the arbitrator address
     * @param _arbitrator <address> - The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external onlyGovernance {
        arbitrator = _arbitrator;
    }

    /**
     * @dev Accept tokens
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     * @param _data <bytes> - Extra data payload
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token), "Caller is not the GRT token");

        // Decode subgraphID
        bytes32 _subgraphID = _data.slice(0, 32).toBytes32(0);

        // Decode attestation
        bytes memory _attestation = _data.slice(32, ATTESTATION_SIZE_BYTES);
        require(
            _attestation.length == ATTESTATION_SIZE_BYTES,
            "Signature must be 192 bytes long"
        );

        // Decode attestation signature
        bytes memory _sig = _data.slice(
            32 + ATTESTATION_SIZE_BYTES,
            SIGNATURE_SIZE_BYTES
        );
        require(
            _sig.length == SIGNATURE_SIZE_BYTES,
            "Signature must be 65 bytes long"
        );

        createDispute(_attestation, _sig, _subgraphID, _from, _value);

        return true;
    }

    /**
     * @dev The arbitrator can accept a dispute as being valid
     * @param _disputeID <bytes32> - ID of the dispute to be accepted
     */
    function acceptDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        bytes32 _subgraphID = disputes[_disputeID].subgraphID;
        address _fisherman = disputes[_disputeID].fisherman;
        address _indexNode = disputes[_disputeID].indexNode;
        uint256 _depositAmount = disputes[_disputeID].depositAmount;

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Have staking slash the index node and reward the fisherman
        // Give the fisherman a reward equal to the slashingPercent of the indexer's stake
        uint256 _stake = staking.getIndexingNodeStake(_subgraphID, _indexNode);
        uint256 _reward = getRewardForStake(_stake);
        assert(_reward <= _stake); // sanity check on fixed-point math
        staking.slash(_subgraphID, _indexNode, _reward, _fisherman);

        // Give the fisherman their deposit back
        require(
            token.transfer(_fisherman, _depositAmount),
            "Error sending dispute deposit"
        );

        // Log event that we awarded _fisherman _reward in resolving _disputeID
        emit DisputeAccepted(
            _disputeID,
            _subgraphID,
            _indexNode,
            _fisherman,
            _reward
        );
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid
     * @param _disputeID <bytes32> - ID of the dispute to be rejected
     */
    function rejectDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        bytes32 _subgraphID = disputes[_disputeID].subgraphID;
        address _fisherman = disputes[_disputeID].fisherman;
        address _indexNode = disputes[_disputeID].indexNode;
        uint256 _depositAmount = disputes[_disputeID].depositAmount;

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Burn the fisherman's deposit
        token.burn(_depositAmount);

        emit DisputeRejected(
            _disputeID,
            _subgraphID,
            _indexNode,
            _fisherman,
            _depositAmount
        );
    }

    /**
     * @dev The arbitrator can disregard a dispute
     * @param _disputeID <bytes32> - ID of the dispute to be disregarded
     */
    function ignoreDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        bytes32 _subgraphID = disputes[_disputeID].subgraphID;
        address _fisherman = disputes[_disputeID].fisherman;
        address _indexNode = disputes[_disputeID].indexNode;
        uint256 _depositAmount = disputes[_disputeID].depositAmount;

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Return deposit to the fisherman
        require(
            token.transfer(_fisherman, _depositAmount),
            "Error sending dispute deposit"
        );

        emit DisputeIgnored(
            _disputeID,
            _subgraphID,
            _indexNode,
            _fisherman,
            _depositAmount
        );
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _attestation <Attestation> - Attestation message
     * @param _sig <bytes> - Attestation signature
     * @param _subgraphID <bytes32> - subgraphID that Attestation message
     *                                contains (in request raw object at CID)
     * @param _fisherman <address> - Creator of dispute
     * @param _amount <uint256> - Amount of tokens staked
     */
    function createDispute(
        bytes memory _attestation,
        bytes memory _sig,
        bytes32 _subgraphID,
        address _fisherman,
        uint256 _amount
    ) private {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        bytes32 _disputeID = getDisputeID(_attestation);

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // Note: The signer of the attestation is the indexNode that served it
        address _indexNode = _disputeID.recover(_sig);

        // Get staked amount on the served subgraph by indexer
        uint256 _stake = staking.getIndexingNodeStake(_subgraphID, _indexNode);

        // This also validates that indexer node exists
        require(
            _stake > 0,
            "Dispute has no stake on the subgraph by the indexer node"
        );

        // Ensure that fisherman has posted at least that amount
        require(
            _amount >= getRewardForStake(_stake),
            "Dispute deposit under minimum required"
        );

        // A fisherman can only open one dispute for a given index node / subgraphID at a time
        require(!isDisputeCreated(_disputeID), "Dispute already created"); // Must be empty

        // Store dispute
        disputes[_disputeID] = Dispute(
            _subgraphID,
            _indexNode,
            _fisherman,
            _amount
        );

        // Log event that new dispute was created against IndexNode
        emit DisputeCreated(
            _disputeID,
            _subgraphID,
            _indexNode,
            _fisherman,
            _attestation
        );
    }
}
