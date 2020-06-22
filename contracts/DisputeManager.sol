pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";
import "./GraphToken.sol";
import "./Staking.sol";

/*
 * @title DisputeManager
 * @dev Provides a way to align the incentives of participants ensuring that query results are trustful.
 */
contract DisputeManager is Governed {
    using SafeMath for uint256;

    // Disputes contain info neccessary for the Arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphDeploymentID;
        address indexer;
        address fisherman;
        uint256 deposit;
    }

    // -- Attestation --

    // Receipt content sent from indexer in response to request
    struct Receipt {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
    }

    // Attestation sent from indexer in response to a request
    struct Attestation {
        bytes32 requestCID;
        bytes32 responseCID;
        bytes32 subgraphDeploymentID;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    uint256 private constant ATTESTATION_SIZE_BYTES = 161;
    uint256 private constant RECEIPT_SIZE_BYTES = 96;

    // -- EIP-712  --

    bytes32 private constant DOMAIN_TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
    );
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;
    bytes32 private constant RECEIPT_TYPE_HASH = keccak256(
        "Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)"
    );

    // 100% in parts per million
    uint256 private constant MAX_PPM = 1000000;

    // -- State --

    bytes32 private DOMAIN_SEPARATOR;

    // Disputes created : disputeID => Dispute
    // disputeID is the hash of attestation data
    mapping(bytes32 => Dispute) public disputes;

    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Minimum deposit required to create a Dispute
    uint256 public minimumDeposit;

    // Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public fishermanRewardPercentage;

    // Percentage of indexer stake to slash on disputes
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint256 public slashingPercentage;

    // Graph Token address
    GraphToken public token;

    // Staking contract used for slashing
    Staking public staking;

    // -- Events --

    /**
     * @dev Emitted when `disputeID` is created for `subgraphDeploymentID` and `indexer`
     * by `fisherman`.
     * The event emits the amount `tokens` deposited by the fisherman and `attestation` submitted.
     */
    event DisputeCreated(
        bytes32 disputeID,
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens,
        bytes attestation
    );

    /**
     * @dev Emitted when arbitrator accepts a `disputeID` for `subgraphDeploymentID` and `indexer`
     * created by `fisherman`.
     * The event emits the amount `tokens` transferred to the fisherman, the deposit plus reward.
     */
    event DisputeAccepted(
        bytes32 disputeID,
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator rejects a `disputeID` for `subgraphDeploymentID` and `indexer`
     * created by `fisherman`.
     * The event emits the amount `tokens` burned from the fisherman deposit.
     */
    event DisputeRejected(
        bytes32 disputeID,
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator draw a `disputeID` for `subgraphDeploymentID` and `indexer`
     * created by `fisherman`.
     * The event emits the amount `tokens` used as deposit and returned to the fisherman.
     */
    event DisputeDrawn(
        bytes32 disputeID,
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
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
     * @param _fishermanRewardPercentage Percent of slashed funds the fisherman gets (in PPM)
     * @param _slashingPercentage Percentage of indexer stake slashed after a dispute
     */
    constructor(
        address _governor,
        address _arbitrator,
        address _token,
        address _staking,
        uint256 _minimumDeposit,
        uint256 _fishermanRewardPercentage,
        uint256 _slashingPercentage
    ) public Governed(_governor) {
        arbitrator = _arbitrator;
        token = GraphToken(_token);
        staking = Staking(_staking);
        minimumDeposit = _minimumDeposit;
        fishermanRewardPercentage = _fishermanRewardPercentage;
        slashingPercentage = _slashingPercentage;

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME_HASH,
                DOMAIN_VERSION_HASH,
                _getChainID(),
                address(this),
                DOMAIN_SALT
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
     * @dev Get the fisherman reward for a given indexer stake
     * @notice Return the fisherman reward based on the `_indexer` stake
     * @param _indexer Indexer to be slashed
     * @return Reward calculated as percentage of the indexer slashed funds
     */
    function getTokensToReward(address _indexer) public view returns (uint256) {
        uint256 value = getTokensToSlash(_indexer);
        return fishermanRewardPercentage.mul(value).div(MAX_PPM);
    }

    /**
     * @dev Get the amount of tokens to slash for an indexer based on the stake
     * @param _indexer Address of the indexer
     * @return Amount of tokens to slash
     */
    function getTokensToSlash(address _indexer) public view returns (uint256) {
        uint256 tokens = staking.getIndexerStakedTokens(_indexer); // slashable tokens
        return slashingPercentage.mul(tokens).div(MAX_PPM);
    }

    /**
     * @dev Get the message hash that an indexer used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @notice Return the message hash used to sign the receipt
     * @param _receipt Receipt returned by indexer and submitted by fisherman
     * @return Message hash used to sign the receipt
     */
    function encodeHashReceipt(Receipt memory _receipt) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-191 encoding pad, EIP-712 version 1
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            RECEIPT_TYPE_HASH,
                            _receipt.requestCID,
                            _receipt.responseCID,
                            _receipt.subgraphDeploymentID
                        ) // EIP 712-encoded message hash
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
        arbitrator = _arbitrator;
        emit ParameterUpdated("arbitrator");
    }

    /**
     * @dev Set the minimum deposit required to create a dispute
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external onlyGovernor {
        minimumDeposit = _minimumDeposit;
        emit ParameterUpdated("minimumDeposit");
    }

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of indexer stake
     */
    function setFishermanRewardPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Reward percentage must be below or equal to MAX_PPM");
        fishermanRewardPercentage = _percentage;
        emit ParameterUpdated("fishermanRewardPercentage");
    }

    /**
     * @dev Set the percentage used for slashing indexers
     * @param _percentage Percentage used for slashing
     */
    function setSlashingPercentage(uint256 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Slashing percentage must be below or equal to MAX_PPM");
        slashingPercentage = _percentage;
        emit ParameterUpdated("slashingPercentage");
    }

    /**
     * @dev Set the staking contract used for slashing
     * @notice Update the staking contract to `_staking`
     * @param _staking Address of the staking contract
     */
    function setStaking(Staking _staking) external onlyGovernor {
        staking = _staking;
        emit ParameterUpdated("staking");
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve.
     * This function is called by a fisherman and will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @param _deposit Amount of tokens staked as deposit
     */
    function createDispute(bytes calldata _attestationData, uint256 _deposit) external
    {
        address fisherman = msg.sender;

        // Ensure that fisherman has staked at least the minimum amount
        require(_deposit >= minimumDeposit, "Dispute deposit is under minimum required");

        // Transfer tokens to deposit from fisherman to this contract
        require(
            token.transferFrom(fisherman, address(this), _deposit),
            "Cannot transfer tokens to deposit"
        );

        // Create a dispute using the received attestation and deposit
        _createDispute(fisherman, _deposit, _attestationData);
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

        // Have staking contract slash the indexer and reward the fisherman
        // Give the fisherman a reward equal to the fishermanRewardPercentage of slashed amount
        uint256 tokensToSlash = getTokensToSlash(dispute.indexer);
        uint256 tokensToReward = getTokensToReward(dispute.indexer);

        require(tokensToSlash > 0, "Dispute has zero tokens to slash");
        staking.slash(dispute.indexer, tokensToSlash, tokensToReward, dispute.fisherman);

        // Give the fisherman their deposit back
        require(
            token.transfer(dispute.fisherman, dispute.deposit),
            "Error sending dispute deposit"
        );

        emit DisputeAccepted(
            _disputeID,
            dispute.subgraphDeploymentID,
            dispute.indexer,
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
            dispute.subgraphDeploymentID,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev The arbitrator can draw dispute
     * @notice Ignore a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be disregarded
     */
    function drawDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy protection

        // Return deposit to the fisherman
        require(
            token.transfer(dispute.fisherman, dispute.deposit),
            "Error sending dispute deposit"
        );

        emit DisputeDrawn(
            _disputeID,
            dispute.subgraphDeploymentID,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     */
    function _createDispute(address _fisherman, uint256 _deposit, bytes memory _attestationData) private {
        // Check attestation data length
        require(_attestationData.length == ATTESTATION_SIZE_BYTES, "Attestation must be 161 bytes long");

        // Decode attestation
        Attestation memory attestation = _parseAttestation(_attestationData);

        // Get attestation signer, channelID
        address channelID = _recoverAttestationSigner(attestation);

        // Get the indexer that created the channel and signed the attestation
        (bytes memory publicKey, address indexer, bytes32 subgraphDeploymentID) = staking.channels(channelID);
        require(indexer != address(0), "Indexer cannot be found for the attestation");
        require(
            subgraphDeploymentID == attestation.subgraphDeploymentID,
            "Channel and attestation subgraphDeploymentID must match"
        );
        require(keccak256(publicKey) != keccak256(""), "Public key cannot be found for the attestation");

        // Create a disputeID
        bytes32 disputeID = keccak256(
            abi.encodePacked(
                attestation.requestCID,
                attestation.responseCID,
                attestation.subgraphDeploymentID,
                indexer
            )
        );

        // This also validates that indexer exists
        require(staking.hasStake(indexer), "Dispute has no stake by the indexer");

        // A fisherman can only open one dispute for a (indexer, subgraphDeploymentID) at a time
        require(!isDisputeCreated(disputeID), "Dispute already created"); // Must be empty

        // Store dispute
        disputes[disputeID] = Dispute(
            attestation.subgraphDeploymentID,
            indexer,
            _fisherman,
            _deposit
        );

        emit DisputeCreated(
            disputeID,
            attestation.subgraphDeploymentID,
            indexer,
            _fisherman,
            _deposit,
            _attestationData
        );
    }

    /**
     * @dev Recover the signer address of the `_attestation`
     * @param _attestation The attestation struct
     * @return Signer address
     */
    function _recoverAttestationSigner(Attestation memory _attestation) private view returns (address) {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        Receipt memory receipt = Receipt(
            _attestation.requestCID,
            _attestation.responseCID,
            _attestation.subgraphDeploymentID
        );
        bytes32 messageHash = encodeHashReceipt(receipt);

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // NOTE: The signer of the attestation is the indexer that served the request
        return _recover(messageHash, _attestation.v, _attestation.r, _attestation.s);
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

    /**
     * @dev Parse the bytes attestation into a struct from `_data`
     * @return Attestation struct
     */
    function _parseAttestation(bytes memory _data) private pure returns (Attestation memory) {
        // Decode receipt
        (bytes32 requestCID, bytes32 responseCID, bytes32 subgraphDeploymentID) = abi.decode(
            _data, (bytes32, bytes32, bytes32)
        );

        // Decode signature
        // Signature is expected to be in the order defined in the Attestation struct
        uint8 v = _toUint8(_data, RECEIPT_SIZE_BYTES);
        bytes32 r = _toBytes32(_data, RECEIPT_SIZE_BYTES + 1);
        bytes32 s = _toBytes32(_data, RECEIPT_SIZE_BYTES + 33);

        return Attestation(requestCID, responseCID, subgraphDeploymentID, v, r, s);
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * signature `v`, `r', `s`. This address can then be used for verification purposes.
     * @return The address recovered from the hash and signature.
     */
    function _recover(bytes32 _hash, uint8 _v, bytes32 _r, bytes32 _s) private pure returns (address) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(_s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert("ECDSA: invalid signature 's' value");
        }

        if (_v != 27 && _v != 28) {
            revert("ECDSA: invalid signature 'v' value");
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(_hash, _v, _r, _s);
        require(signer != address(0), "ECDSA: invalid signature");

        return signer;
    }

    /**
     * @dev Parse a uint8 from `_bytes` starting at offset `_start`
     * @return uint8 value
     */
    function _toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_bytes.length >= (_start + 1), "Bytes: out of bounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    /**
     * @dev Parse a bytes32 from `_bytes` starting at offset `_start`
     * @return bytes32 value
     */
    function _toBytes32(bytes memory _bytes, uint256 _start) internal pure returns (bytes32) {
        require(_bytes.length >= (_start + 32), "Bytes: out of bounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
}
