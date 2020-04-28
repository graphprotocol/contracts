pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

/*
 * @title Dispute management
 * @notice Provides a way to align the incentives of participants ensuring that Query Results are trustful.
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

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // 1 basis point (0.01%) is 100 parts per million (PPM)
    uint256 private constant BASIS_PT = 100;

    // -- State --

    bytes32 private DOMAIN_SEPARATOR;

    // Disputes created by the Fisherman or other authorized entites
    // @key _disputeID - Hash of readIndex data + disputer data
    mapping(bytes32 => Dispute) public disputes;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // Percentage of index node slashed funds to assign as a reward to fisherman in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public rewardPercentage;

    // Percentage of index node stake to slash on disputes
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
     * @param _governor Owner address of this contract
     * @param _token Address of the Graph Protocol token
     * @param _arbitrator Arbitrator role
     * @param _staking Address of the staking contract used for slashing
     * @param _minimumDeposit Minimum deposit required to create a Dispute
     * @param _rewardPercentage Percent of slashed funds the fisherman gets (in PPM)
     * @param _slashingPercentage Percentage of index node stake slashed after a dispute
     */
    constructor(
        address _governor,
        address _arbitrator,
        address _token,
        address _staking,
        uint256 _minimumDeposit,
        uint256 _rewardPercentage,
        uint256 _slashingPercentage
    ) public Governed(_governor) {
        _setArbitrator(_arbitrator);
        token = GraphToken(_token);
        staking = Staking(_staking);
        minimumDeposit = _minimumDeposit;
        rewardPercentage = _rewardPercentage;
        slashingPercentage = _slashingPercentage;

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME_HASH,
                DOMAIN_VERSION_HASH,
                _getChainID(),
                address(this)
            )
        );
    }

    /**
     * @dev Return whether a dispute exists or not
     * @notice Return if dispute with ID `_disputeID` exists
     * @param _disputeID True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeID) public view returns (bool) {
        return disputes[_disputeID].fisherman != address(0);
    }

    /**
     * @dev Get the fisherman reward for a given index node stake
     * @notice Return the fisherman reward based on the `_indexNode` stake
     * @param _indexNode IndexNode to be slashed
     * @return Reward calculated as percentage of the index node slashed funds
     */
    function getTokensToReward(address _indexNode) public view returns (uint256) {
        uint256 value = getTokensToSlash(_indexNode);
        return rewardPercentage.mul(value).div(MAX_PPM); // rewardPercentage is in PPM
    }

    /**
     * @dev Get the amount of tokens to slash for an index node based on the stake
     * @param _indexNode Address of the index node
     * @return Amount of tokens to slash
     */
    function getTokensToSlash(address _indexNode) public view returns (uint256) {
        uint256 tokens = staking.getIndexNodeStakeTokens(_indexNode); // slashable tokens
        return slashingPercentage.mul(tokens).div(MAX_PPM); // slashingPercentage is in PPM
    }

    /**
     * @dev Get the hash of encoded message to use as disputeID
     * @notice Return the disputeID for a particular attestation
     * @param _attestation Signed Attestation message
     * @return Hash of encoded message used as disputeID
     */
    function getDisputeID(bytes memory _attestation) public view returns (bytes32) {
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
     * @param _arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external onlyGovernor {
        _setArbitrator(_arbitrator);
    }

    /**
     * @dev Set the arbitrator address
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(_arbitrator != address(0), "Cannot set arbitrator to empty address");
        arbitrator = _arbitrator;
    }

    /**
     * @dev Set the minimum deposit required to create a dispute
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external onlyGovernor {
        minimumDeposit = _minimumDeposit;
    }

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of index node stake
     */
    function setRewardPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Reward percentage must be below or equal to MAX_PPM");

        rewardPercentage = _percentage;
    }

    /**
     * @dev Set the percentage used for slashing index nodes
     * @param _percentage Percentage used for slashing
     */
    function setSlashingPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Slashing percentage must be below or equal to MAX_PPM");
        slashingPercentage = _percentage;
    }

    /**
     * @dev Accept tokens
     * @notice Receive Graph tokens
     * @param _from Token holder's address
     * @param _value Amount of Graph Tokens
     * @param _data Extra data payload
     */
    function tokensReceived(address _from, uint256 _value, bytes calldata _data)
        external
        returns (bool)
    {
        // Make sure the token is the caller of this function
        require(msg.sender == address(token), "Caller is not the GRT token contract");

        // Decode subgraphID
        bytes32 subgraphID = _data.slice(0, 32).toBytes32(0);

        // Decode attestation
        bytes memory attestation = _data.slice(32, ATTESTATION_SIZE_BYTES);
        require(attestation.length == ATTESTATION_SIZE_BYTES, "Signature must be 192 bytes long");

        // Decode attestation signature
        bytes memory sig = _data.slice(32 + ATTESTATION_SIZE_BYTES, SIGNATURE_SIZE_BYTES);
        require(sig.length == SIGNATURE_SIZE_BYTES, "Signature must be 65 bytes long");

        _createDispute(attestation, sig, subgraphID, _from, _value);

        return true;
    }

    /**
     * @dev The arbitrator can accept a dispute as being valid
     * @notice Accept a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be accepted
     */
    function acceptDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Have staking contract slash the index node and reward the fisherman
        // Give the fisherman a reward equal to the rewardPercentage of the index node slashed amount
        uint256 tokensToReward = getTokensToReward(dispute.indexNode);
        uint256 tokensToSlash = getTokensToSlash(dispute.indexNode);
        staking.slash(dispute.indexNode, tokensToSlash, tokensToReward, dispute.fisherman);

        // Give the fisherman their deposit back
        require(
            token.transfer(dispute.fisherman, dispute.deposit),
            "Error sending dispute deposit"
        );

        emit DisputeAccepted(
            _disputeID,
            dispute.subgraphID,
            dispute.indexNode,
            dispute.fisherman,
            dispute.deposit.add(tokensToReward)
        );
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid
     * @notice Reject a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be rejected
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
     * @param _disputeID ID of the dispute to be disregarded
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
     * @param _attestation Attestation message
     * @param _sig Attestation signature
     * @param _subgraphID subgraphID that Attestation message
     *                                contains (in request raw object at CID)
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     */
    function _createDispute(
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

        // This also validates that index node node exists
        require(staking.hasStake(indexNode), "Dispute has no stake by the index node");

        // Ensure that fisherman has staked at least the minimum amount
        require(_deposit >= minimumDeposit, "Dispute deposit under minimum required");

        // A fisherman can only open one dispute for a given index node / subgraphID at a time
        require(!isDisputeCreated(disputeID), "Dispute already created"); // Must be empty

        // Store dispute
        disputes[disputeID] = Dispute(_subgraphID, indexNode, _fisherman, _deposit);

        emit DisputeCreated(disputeID, _subgraphID, indexNode, _fisherman, _attestation);
    }

    /**
     * @dev Get the running network chain ID
     * @return The chain ID
     */
    function _getChainID() private pure returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
}
