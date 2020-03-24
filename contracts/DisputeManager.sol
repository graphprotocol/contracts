pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Dispute management
 * @notice Provides a way to align the incentives of  participants ensuring that Query Results are trustful.
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

    // Disputes contain info neccessary for the Arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphID;
        address indexNode;
        address fisherman;
        uint256 deposit;
    }

    // -- Attestation --

    // Store IPFS hash as 32 byte hash and 2 byte hash function
    // Note: Not future proof against IPFS planned updates to support multihash, which would require a len field
    // Note: hashFunction - 0x1220 is 'Qm', or SHA256 with 32 byte length
    struct IpfsHash {
        bytes32 hash;
        uint16 hashFunction;
    }

    // Signed message sent from IndexNode in response to a request
    // Note: Message is located at the given IPFS content address
    struct Attestation {
        // Content Identifier for request message sent from user to indexing node
        IpfsHash requestCID;
        // Content Identifier for signed response message from indexing node
        IpfsHash responseCID;
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
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0.1");
    bytes32 private constant ATTESTATION_TYPE_HASH = keccak256(
        "Attestation(IpfsHash requestCID,IpfsHash responseCID,uint256 gasUsed,uint256 responseNumBytes)IpfsHash(bytes32 hash,uint16 hashFunction)"
    );
    // 1 - mainnet // TODO: EIP-1344 adds support for the Chain ID opcode
    uint256 private constant CHAIN_ID = 1;
    bytes32 private DOMAIN_SEPARATOR;

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeID - Hash of readIndex data + disputer data
    mapping(bytes32 => Dispute) public disputes;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // Percentage of index node stake to slash in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercentage;

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
        uint256 deposit
    );

    event DisputeRejected(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        uint256 deposit
    );

    event DisputeIgnored(
        bytes32 disputeID,
        bytes32 indexed subgraphID,
        address indexed indexNode,
        address indexed fisherman,
        uint256 deposit
    );

    modifier onlyArbitrator {
        require(msg.sender == arbitrator, "Caller is not the Arbitrator");
        _;
    }

    /**
     * @dev Contract Constructor
     * @param _governor <address> - Owner address of this contract
     * @param _token <address> - Address of the Graph Protocol token
     * @param _arbitrator <address> - Arbitrator role
     * @param _staking <address> - Address of the staking contract used for slashing
     * @param _slashingPercentage <uint256> - Percent of stake the fisherman gets on slashing (in PPM)
     * @param _minimumDeposit <uint256> - Minimum deposit required to create a Dispute
     */
    constructor(
        address _governor,
        address _token,
        address _arbitrator,
        address _staking,
        uint256 _slashingPercentage,
        uint256 _minimumDeposit
    ) public Governed(_governor) {
        _setArbitrator(_arbitrator);
        token = GraphToken(_token);
        staking = Staking(_staking);

        minimumDeposit = _minimumDeposit;
        slashingPercentage = _slashingPercentage;

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
     * @notice Return if dispute with ID `_disputeID` exists
     * @param _disputeID <bool> - True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeID) public view returns (bool) {
        return disputes[_disputeID].fisherman != address(0);
    }

    /**
     * @dev Get the amount of fisherman reward for a given amount of stake
     * @notice Return the fisherman reward for a stake of `_value`
     * @param _value <uint256> - Amount of validator's stake
     * @return <uint256> - Percentage of validator's stake to be considered a reward
     */
    function getRewardForStake(uint256 _value) public view returns (uint256) {
        return slashingPercentage.mul(_value).div(MAX_PPM); // slashingPercentage is in PPM
    }

    /**
     * @dev Get the hash of encoded message to use as disputeID
     * @notice Return the disputeID for a particular attestation
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
                    "\x19\x01", // EIP-191 encoding pad, EIP-712 version 1
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(ATTESTATION_TYPE_HASH, _attestation) // EIP 712-encoded message hash
                    )
                )
            );
    }

    /**
     * @dev Set the arbitrator address
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator <address> - The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external onlyGovernance {
        _setArbitrator(_arbitrator);
    }

    /**
     * @dev Set the arbitrator address
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator <address> - The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(
            _arbitrator != address(0),
            "Cannot set arbitrator to empty address"
        );
        arbitrator = _arbitrator;
    }

    /**
     * @dev Set the minimum deposit required to create a dispute
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit <uint256> - The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit)
        external
        onlyGovernance
    {
        minimumDeposit = _minimumDeposit;
    }

    /**
     * @dev Set the percent that the fisherman gets when slashing occurs
     * @notice Update the slashing percent to `_slashingPercentage`
     * @param _slashingPercentage <uint256> - Slashing percentage
     */
    function setSlashingPercentage(uint256 _slashingPercentage)
        external
        onlyGovernance
    {
        // Must be within 0% to 100% (inclusive)
        require(
            _slashingPercentage >= 0,
            "Slashing percentage must above or equal to 0"
        );
        require(
            _slashingPercentage <= MAX_PPM,
            "Slashing percentage must be below or equal to MAX_PPM"
        );

        slashingPercentage = _slashingPercentage;
    }

    /**
     * @dev Accept tokens
     * @notice Receive Graph tokens
     * @param _from <address> - Token holder's address
     * @param _value <uint256> - Amount of Graph Tokens
     * @param _data <bytes> - Extra data payload
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(
            msg.sender == address(token),
            "Caller is not the GRT token contract"
        );

        // Decode subgraphID
        bytes32 subgraphID = _data.slice(0, 32).toBytes32(0);

        // Decode attestation
        bytes memory attestation = _data.slice(32, ATTESTATION_SIZE_BYTES);
        require(
            attestation.length == ATTESTATION_SIZE_BYTES,
            "Signature must be 192 bytes long"
        );

        // Decode attestation signature
        bytes memory sig = _data.slice(
            32 + ATTESTATION_SIZE_BYTES,
            SIGNATURE_SIZE_BYTES
        );
        require(
            sig.length == SIGNATURE_SIZE_BYTES,
            "Signature must be 65 bytes long"
        );

        createDispute(attestation, sig, subgraphID, _from, _value);

        return true;
    }

    /**
     * @dev The arbitrator can accept a dispute as being valid
     * @notice Accept a dispute with ID `_disputeID`
     * @param _disputeID <bytes32> - ID of the dispute to be accepted
     */
    function acceptDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Have staking slash the index node and reward the fisherman
        // Give the fisherman a reward equal to the slashingPercentage of the indexer's stake
        uint256 stake = staking.getIndexingNodeStake(
            dispute.subgraphID,
            dispute.indexNode
        );
        uint256 reward = getRewardForStake(stake);
        assert(reward <= stake); // sanity check on fixed-point math
        staking.slash(
            dispute.subgraphID,
            dispute.indexNode,
            reward,
            dispute.fisherman
        );

        // Give the fisherman their deposit back
        require(
            token.transfer(dispute.fisherman, dispute.deposit),
            "Error sending dispute deposit"
        );

        // Log event that we awarded _fisherman _reward in resolving _disputeID
        emit DisputeAccepted(
            _disputeID,
            dispute.subgraphID,
            dispute.indexNode,
            dispute.fisherman,
            reward
        );
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid
     * @notice Reject a dispute with ID `_disputeID`
     * @param _disputeID <bytes32> - ID of the dispute to be rejected
     */
    function rejectDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Burn the fisherman's deposit
        token.burn(dispute.deposit);

        emit DisputeRejected(
            _disputeID,
            dispute.subgraphID,
            dispute.indexNode,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev The arbitrator can disregard a dispute
     * @notice Ignore a dispute with ID `_disputeID`
     * @param _disputeID <bytes32> - ID of the dispute to be disregarded
     */
    function ignoreDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Return deposit to the fisherman
        require(
            token.transfer(dispute.fisherman, dispute.deposit),
            "Error sending dispute deposit"
        );

        emit DisputeIgnored(
            _disputeID,
            dispute.subgraphID,
            dispute.indexNode,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _attestation <Attestation> - Attestation message
     * @param _sig <bytes> - Attestation signature
     * @param _subgraphID <bytes32> - subgraphID that Attestation message
     *                                contains (in request raw object at CID)
     * @param _fisherman <address> - Creator of dispute
     * @param _deposit <uint256> - Amount of tokens staked as deposit
     */
    function createDispute(
        bytes memory _attestation,
        bytes memory _sig,
        bytes32 _subgraphID,
        address _fisherman,
        uint256 _deposit
    ) private {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        bytes32 disputeID = getDisputeID(_attestation);

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // Note: The signer of the attestation is the indexNode that served it
        address indexNode = disputeID.recover(_sig);

        // Get staked amount on the served subgraph by indexer
        uint256 stake = staking.getIndexingNodeStake(_subgraphID, indexNode);

        // This also validates that indexer node exists
        require(
            stake > 0,
            "Dispute has no stake on the subgraph by the indexer node"
        );

        // Ensure that fisherman has staked at least that amount
        require(
            _deposit >= minimumDeposit,
            "Dispute deposit under minimum required"
        );

        // A fisherman can only open one dispute for a given index node / subgraphID at a time
        require(!isDisputeCreated(disputeID), "Dispute already created"); // Must be empty

        // Store dispute
        disputes[disputeID] = Dispute(
            _subgraphID,
            indexNode,
            _fisherman,
            _deposit
        );

        // Log event that new dispute was created against IndexNode
        emit DisputeCreated(
            disputeID,
            _subgraphID,
            indexNode,
            _fisherman,
            _attestation
        );
    }
}
