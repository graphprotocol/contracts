pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../governance/Manager.sol";

/*
 * @title DisputeManager
 * @dev Provides a way to align the incentives of participants ensuring that query results are trustful.
 */
contract DisputeManager is Manager {
    using SafeMath for uint256;

    // Disputes contain info neccessary for the Arbitrator to verify and resolve
    struct Dispute {
        bytes32 subgraphDeploymentID;
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeID;
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
    bytes32
        private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;
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

    // Minimum stake an indexer needs to have to allow be disputed
    uint256 public minimumIndexerStake;

    // Percentage of indexer slashed funds to assign as a reward to fisherman in successful dispute
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public fishermanRewardPercentage;

    // Percentage of indexer stake to slash on disputes
    // Parts per million. (Allows for 4 decimal points, 999,999 = 99.9999%)
    uint32 public slashingPercentage;

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

    /**
     * @dev Emitted when two disputes are in conflict to link them.
     * This event will be emitted after each DisputeCreated event is emitted
     * for each of the individual disputes.
     */
    event DisputeLinked(bytes32 disputeID1, bytes32 disputeID2);

    /**
     * @dev Check if the caller is the arbitrator.
     */
    modifier onlyArbitrator {
        require(msg.sender == arbitrator, "Caller is not the Arbitrator");
        _;
    }

    /**
     * @dev Contract Constructor
     * @param _arbitrator Arbitrator role
     * @param _minimumDeposit Minimum deposit required to create a Dispute
     * @param _fishermanRewardPercentage Percent of slashed funds for fisherman (basis points)
     * @param _slashingPercentage Percentage of indexer stake slashed (basis points)
     */
    constructor(
        address _controller,
        address _arbitrator,
        uint256 _minimumDeposit,
        uint32 _fishermanRewardPercentage,
        uint32 _slashingPercentage
    ) public {
        Manager._initialize(_controller);
        arbitrator = _arbitrator;
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
     * @dev Return whether a dispute exists or not.
     * @notice Return if dispute with ID `_disputeID` exists
     * @param _disputeID True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeID) public view returns (bool) {
        return disputes[_disputeID].fisherman != address(0);
    }

    /**
     * @dev Get the fisherman reward for a given indexer stake.
     * @notice Return the fisherman reward based on the `_indexer` stake
     * @param _indexer Indexer to be slashed
     * @return Reward calculated as percentage of the indexer slashed funds
     */
    function getTokensToReward(address _indexer) public view returns (uint256) {
        uint256 tokens = getTokensToSlash(_indexer);
        if (tokens == 0) {
            return 0;
        }
        return uint256(fishermanRewardPercentage).mul(tokens).div(MAX_PPM);
    }

    /**
     * @dev Get the amount of tokens to slash for an indexer based on the current stake.
     * @param _indexer Address of the indexer
     * @return Amount of tokens to slash
     */
    function getTokensToSlash(address _indexer) public view returns (uint256) {
        uint256 tokens = staking().getIndexerStakedTokens(_indexer); // slashable tokens
        if (tokens == 0) {
            return 0;
        }
        return uint256(slashingPercentage).mul(tokens).div(MAX_PPM);
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
     * @dev Set the arbitrator address.
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external onlyGovernor {
        arbitrator = _arbitrator;
        emit ParameterUpdated("arbitrator");
    }

    /**
     * @dev Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external onlyGovernor {
        minimumDeposit = _minimumDeposit;
        emit ParameterUpdated("minimumDeposit");
    }

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of indexer stake
     */
    function setFishermanRewardPercentage(uint32 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Reward percentage must be below or equal to MAX_PPM");
        fishermanRewardPercentage = _percentage;
        emit ParameterUpdated("fishermanRewardPercentage");
    }

    /**
     * @dev Set the percentage used for slashing indexers.
     * @param _percentage Percentage used for slashing
     */
    function setSlashingPercentage(uint32 _percentage) external onlyGovernor {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Slashing percentage must be below or equal to MAX_PPM");
        slashingPercentage = _percentage;
        emit ParameterUpdated("slashingPercentage");
    }

    /**
     * @dev Set the minimum indexer stake required to allow be disputed.
     * @param _minimumIndexerStake Minimum indexer stake
     */
    function setMinimumIndexerStake(uint256 _minimumIndexerStake) external onlyGovernor {
        minimumIndexerStake = _minimumIndexerStake;
        emit ParameterUpdated("minimumIndexerStake");
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve.
     * This function is called by a fisherman and will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @param _deposit Amount of tokens staked as deposit
     */
    function createDispute(bytes calldata _attestationData, uint256 _deposit) external {
        address fisherman = msg.sender;

        // Ensure that fisherman has staked at least the minimum amount
        require(_deposit >= minimumDeposit, "Dispute deposit is under minimum required");

        // Transfer tokens to deposit from fisherman to this contract
        require(
            graphToken().transferFrom(fisherman, address(this), _deposit),
            "Cannot transfer tokens to deposit"
        );

        // Create a dispute using the received attestation and deposit
        _createDispute(fisherman, _deposit, _attestationData);
    }

    /**
     * @dev Create disputes for conflicting attestations.
     * A conflicting attestation is a proof presented by two different indexers
     * where for the same request on a subgraph the response is different.
     * For this type of dispute the submitter is not required to present a deposit
     * as one of the attestation is considered to be right.
     * Two linked disputes will be created and if the arbitrator resolve one, the other
     * one will be automatically resolved.
     * @param _attestationData1 First ttestation data submitted
     * @param _attestationData1 Second attestation data submitted
     */
    function createDisputesInConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external {
        address fisherman = msg.sender;

        // Parse each attestation
        Attestation memory attestation1 = _parseAttestation(_attestationData1);
        Attestation memory attestation2 = _parseAttestation(_attestationData2);

        // Test that attestations are conflicting
        require(
            areConflictingAttestations(attestation1, attestation2),
            "Attestations must be in conflict"
        );

        // Create the disputes
        // The deposit is zero for conflicting attestations
        bytes32 dID1 = _createDisputeWithAttestation(fisherman, 0, attestation1, _attestationData1);
        bytes32 dID2 = _createDisputeWithAttestation(fisherman, 0, attestation2, _attestationData2);

        // Store the linked disputes to be resolved
        disputes[dID1].relatedDisputeID = dID2;
        disputes[dID2].relatedDisputeID = dID1;

        // Emit event that links the two created disputes
        emit DisputeLinked(dID1, dID2);
    }

    /**
     * @dev The arbitrator can accept a dispute as being valid.
     * @notice Accept a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be accepted
     */
    function acceptDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy

        // Have staking contract slash the indexer and reward the fisherman
        // Give the fisherman a reward equal to the fishermanRewardPercentage of slashed amount
        uint256 tokensToSlash = getTokensToSlash(dispute.indexer);
        uint256 tokensToReward = getTokensToReward(dispute.indexer);

        require(tokensToSlash > 0, "Dispute has zero tokens to slash");
        staking().slash(dispute.indexer, tokensToSlash, tokensToReward, dispute.fisherman);

        // Give the fisherman their deposit back
        if (dispute.deposit > 0) {
            require(
                graphToken().transfer(dispute.fisherman, dispute.deposit),
                "Error sending dispute deposit"
            );
        }

        // Resolve the conflicting dispute if any
        _resolveDisputeInConflict(dispute);

        emit DisputeAccepted(
            _disputeID,
            dispute.subgraphDeploymentID,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit.add(tokensToReward)
        );
    }

    /**
     * @dev The arbitrator can reject a dispute as being invalid.
     * @notice Reject a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be rejected
     */
    function rejectDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        require(
            !_isDisputeInConflict(dispute),
            "Dispute for conflicting attestation, must accept the related ID to reject"
        );

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy

        // Burn the fisherman's deposit
        if (dispute.deposit > 0) {
            graphToken().burn(dispute.deposit);
        }

        emit DisputeRejected(
            _disputeID,
            dispute.subgraphDeploymentID,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev The arbitrator can draw dispute.
     * @notice Ignore a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be disregarded
     */
    function drawDispute(bytes32 _disputeID) external onlyArbitrator {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");

        Dispute memory dispute = disputes[_disputeID];

        // Resolve dispute
        delete disputes[_disputeID]; // Re-entrancy

        // Return deposit to the fisherman
        if (dispute.deposit > 0) {
            require(
                graphToken().transfer(dispute.fisherman, dispute.deposit),
                "Error sending dispute deposit"
            );
        }

        // Resolve the conflicting dispute
        _resolveDisputeInConflict(dispute);

        emit DisputeDrawn(
            _disputeID,
            dispute.subgraphDeploymentID,
            dispute.indexer,
            dispute.fisherman,
            dispute.deposit
        );
    }

    /**
     * @dev Returns if two attestations are conflicting.
     * Everything must match except for the responseID.
     * @param _attestation1 Attestation
     * @param _attestation2 Attestation
     * @return True if the two attestations are conflicting
     */
    function areConflictingAttestations(
        Attestation memory _attestation1,
        Attestation memory _attestation2
    ) public pure returns (bool) {
        return (_attestation1.requestCID == _attestation2.requestCID &&
            _attestation1.subgraphDeploymentID == _attestation2.subgraphDeploymentID &&
            _attestation1.responseCID != _attestation2.responseCID);
    }

    /**
     * @dev Returns the indexer that signed an attestation.
     * @param _attestation Attestation
     * @return Indexer address
     */
    function getAttestationIndexer(Attestation memory _attestation) public view returns (address) {
        // Get attestation signer, allocationID
        address allocationID = _recoverAttestationSigner(_attestation);

        IStaking.Allocation memory alloc = staking.getAllocation(allocationID);
        require(alloc.indexer != address(0), "Indexer cannot be found for the attestation");
        require(
            alloc.subgraphDeploymentID == _attestation.subgraphDeploymentID,
            "Channel and attestation subgraphDeploymentID must match"
        );
        return alloc.indexer;
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve.
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @return DisputeID
     */
    function _createDispute(
        address _fisherman,
        uint256 _deposit,
        bytes memory _attestationData
    ) internal returns (bytes32) {
        return
            _createDisputeWithAttestation(
                _fisherman,
                _deposit,
                _parseAttestation(_attestationData),
                _attestationData
            );
    }

    /**
     * @dev Create a dispute passing the parsed attestation.
     * This function purpose is to be reused in createDispute() and createDisputeInConflict()
     * to avoid parseAttestation() multiple times
     * `_attestationData` is only passed to be emitted
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _attestation Attestation struct parsed from bytes
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @return DisputeID
     */
    function _createDisputeWithAttestation(
        address _fisherman,
        uint256 _deposit,
        Attestation memory _attestation,
        bytes memory _attestationData
    ) internal returns (bytes32) {
        // Get the indexer that signed the attestation
        address indexer = getAttestationIndexer(_attestation);

        // The indexer is disputable
        require(
            staking.getIndexerStakedTokens(indexer) >= minimumIndexerStake,
            "Dispute under minimum indexer stake amount"
        );

        // Create a disputeID
        bytes32 disputeID = keccak256(
            abi.encodePacked(
                _attestation.requestCID,
                _attestation.responseCID,
                _attestation.subgraphDeploymentID,
                indexer
            )
        );

        // Only one dispute for a (indexer, subgraphDeploymentID) at a time
        require(!isDisputeCreated(disputeID), "Dispute already created"); // Must be empty

        // Store dispute
        disputes[disputeID] = Dispute(
            _attestation.subgraphDeploymentID,
            indexer,
            _fisherman,
            _deposit,
            0 // no related dispute
        );

        emit DisputeCreated(
            disputeID,
            _attestation.subgraphDeploymentID,
            indexer,
            _fisherman,
            _deposit,
            _attestationData
        );

        return disputeID;
    }

    /**
     * @dev Returns whether the dispute is for conflicting attestations or not.
     * @param _dispute Dispute
     * @return True conflicting attestation dispute
     */
    function _isDisputeInConflict(Dispute memory _dispute) internal pure returns (bool) {
        return _dispute.relatedDisputeID != 0;
    }

    /**
     * @dev Resolve the conflicting dispute if there is any for the one passed to this function.
     * @param _dispute Dispute
     * @return True if resolved
     */
    function _resolveDisputeInConflict(Dispute memory _dispute) internal returns (bool) {
        if (_isDisputeInConflict(_dispute)) {
            bytes32 relatedDisputeID = _dispute.relatedDisputeID;
            delete disputes[relatedDisputeID];
            return true;
        }
        return false;
    }

    /**
     * @dev Recover the signer address of the `_attestation`.
     * @param _attestation The attestation struct
     * @return Signer address
     */
    function _recoverAttestationSigner(Attestation memory _attestation)
        internal
        view
        returns (address)
    {
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
    function _getChainID() internal pure returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * @dev Parse the bytes attestation into a struct from `_data`.
     * @return Attestation struct
     */
    function _parseAttestation(bytes memory _data) internal pure returns (Attestation memory) {
        // Check attestation data length
        require(_data.length == ATTESTATION_SIZE_BYTES, "Attestation must be 161 bytes long");

        // Decode receipt
        (bytes32 requestCID, bytes32 responseCID, bytes32 subgraphDeploymentID) = abi.decode(
            _data,
            (bytes32, bytes32, bytes32)
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
    function _recover(
        bytes32 _hash,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal pure returns (address) {
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
     * @dev Parse a uint8 from `_bytes` starting at offset `_start`.
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
     * @dev Parse a bytes32 from `_bytes` starting at offset `_start`.
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
