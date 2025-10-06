// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-small-strings, gas-strict-inequalities

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ECDSA } from "@openzeppelin/contracts/cryptography/ECDSA.sol";

import { Managed } from "../governance/Managed.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { IStaking } from "../staking/IStaking.sol";

import { DisputeManagerV1Storage } from "./DisputeManagerStorage.sol";
import { IDisputeManager } from "./IDisputeManager.sol";

/**
 * @title DisputeManager
 * @author Edge & Node
 * @notice Provides a way to align the incentives of participants by having slashing as deterrent
 * for incorrect behaviour.
 *
 * There are two types of disputes that can be created: Query disputes and Indexing disputes.
 *
 * Query Disputes:
 * Graph nodes receive queries and return responses with signed receipts called attestations.
 * An attestation can be disputed if the consumer thinks the query response was invalid.
 * Indexers use the derived private key for an allocation to sign attestations.
 *
 * Indexing Disputes:
 * Indexers present a Proof of Indexing (POI) when they close allocations to prove
 * they were indexing a subgraph. The Staking contract emits that proof with the format
 * keccak256(indexer.address, POI).
 * Any challenger can dispute the validity of a POI by submitting a dispute to this contract
 * along with a deposit.
 *
 * Arbitration:
 * Disputes can only be accepted, rejected or drawn by the arbitrator role that can be delegated
 * to a EOA or DAO.
 */
contract DisputeManager is DisputeManagerV1Storage, GraphUpgradeable, IDisputeManager {
    using SafeMath for uint256;

    // -- EIP-712  --

    /// @dev EIP-712 domain type hash for signature verification
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    /// @dev EIP-712 domain name hash
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    /// @dev EIP-712 domain version hash
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    /// @dev EIP-712 domain salt for uniqueness
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;
    /// @dev EIP-712 receipt type hash for attestation verification
    bytes32 private constant RECEIPT_TYPE_HASH =
        keccak256("Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)");

    // -- Constants --

    /// @dev Total size of attestation in bytes (receipt + signature)
    uint256 private constant ATTESTATION_SIZE_BYTES = RECEIPT_SIZE_BYTES + SIG_SIZE_BYTES;
    /// @dev Size of receipt in bytes
    uint256 private constant RECEIPT_SIZE_BYTES = 96;

    /// @dev Length of signature R component in bytes
    uint256 private constant SIG_R_LENGTH = 32;
    /// @dev Length of signature S component in bytes
    uint256 private constant SIG_S_LENGTH = 32;
    /// @dev Length of signature V component in bytes
    uint256 private constant SIG_V_LENGTH = 1;
    /// @dev Offset of signature R component in attestation data
    uint256 private constant SIG_R_OFFSET = RECEIPT_SIZE_BYTES;
    /// @dev Offset of signature S component in attestation data
    uint256 private constant SIG_S_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH;
    /// @dev Offset of signature V component in attestation data
    uint256 private constant SIG_V_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH + SIG_S_LENGTH;
    /// @dev Total size of signature in bytes
    uint256 private constant SIG_SIZE_BYTES = SIG_R_LENGTH + SIG_S_LENGTH + SIG_V_LENGTH;

    /// @dev Length of uint8 type in bytes
    uint256 private constant UINT8_BYTE_LENGTH = 1;
    /// @dev Length of bytes32 type in bytes
    uint256 private constant BYTES32_BYTE_LENGTH = 32;

    /// @dev Maximum percentage in parts per million (100%)
    uint256 private constant MAX_PPM = 1000000; // 100% in parts per million

    // -- Events --

    /**
     * @notice Emitted when a query dispute is created for `subgraphDeploymentID` and `indexer`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman and `attestation` submitted.
     * @param disputeID ID of the dispute
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the fisherman creating the dispute
     * @param tokens Amount of tokens deposited by the fisherman
     * @param subgraphDeploymentID Subgraph deployment ID being disputed
     * @param attestation Attestation data submitted
     */
    event QueryDisputeCreated(
        bytes32 indexed disputeID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens,
        bytes32 subgraphDeploymentID,
        bytes attestation
    );

    /**
     * @notice Emitted when an indexing dispute is created for `allocationID` and `indexer`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman.
     * @param disputeID ID of the dispute
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the fisherman creating the dispute
     * @param tokens Amount of tokens deposited by the fisherman
     * @param allocationID Allocation ID being disputed
     */
    event IndexingDisputeCreated(
        bytes32 indexed disputeID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens,
        address allocationID
    );

    /**
     * @notice Emitted when arbitrator accepts a `disputeID` to `indexer` created by `fisherman`.
     * The event emits the amount `tokens` transferred to the fisherman, the deposit plus reward.
     * @param disputeID ID of the dispute
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the fisherman who created the dispute
     * @param tokens Amount of tokens transferred to the fisherman (deposit plus reward)
     */
    event DisputeAccepted(
        bytes32 indexed disputeID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @notice Emitted when arbitrator rejects a `disputeID` for `indexer` created by `fisherman`.
     * The event emits the amount `tokens` burned from the fisherman deposit.
     * @param disputeID ID of the dispute
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the fisherman who created the dispute
     * @param tokens Amount of tokens burned from the fisherman deposit
     */
    event DisputeRejected(
        bytes32 indexed disputeID,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @notice Emitted when arbitrator draw a `disputeID` for `indexer` created by `fisherman`.
     * The event emits the amount `tokens` used as deposit and returned to the fisherman.
     * @param disputeID ID of the dispute
     * @param indexer Address of the indexer being disputed
     * @param fisherman Address of the fisherman who created the dispute
     * @param tokens Amount of tokens used as deposit and returned to the fisherman
     */
    event DisputeDrawn(bytes32 indexed disputeID, address indexed indexer, address indexed fisherman, uint256 tokens);

    /**
     * @notice Emitted when two disputes are in conflict to link them.
     * This event will be emitted after each DisputeCreated event is emitted
     * for each of the individual disputes.
     * @param disputeID1 ID of the first dispute
     * @param disputeID2 ID of the second dispute
     */
    event DisputeLinked(bytes32 indexed disputeID1, bytes32 indexed disputeID2);

    // -- Modifiers --

    /**
     * @notice Internal function to check if the caller is the arbitrator
     */
    function _onlyArbitrator() internal view {
        require(msg.sender == arbitrator, "Caller is not the Arbitrator");
    }

    /**
     * @dev Check if the caller is the arbitrator.
     */
    modifier onlyArbitrator() {
        _onlyArbitrator();
        _;
    }

    /**
     * @dev Check if the dispute exists and is pending
     * @param _disputeID ID of the dispute to check
     */
    modifier onlyPendingDispute(bytes32 _disputeID) {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");
        require(disputes[_disputeID].status == IDisputeManager.DisputeStatus.Pending, "Dispute must be pending");
        _;
    }

    // -- Functions --

    /**
     * @notice Initialize this contract.
     * @param _controller Controller address
     * @param _arbitrator Arbitrator role
     * @param _minimumDeposit Minimum deposit required to create a Dispute
     * @param _fishermanRewardPercentage Percent of slashed funds for fisherman (ppm)
     * @param _qrySlashingPercentage Percentage of indexer stake slashed for query disputes (ppm)
     * @param _idxSlashingPercentage Percentage of indexer stake slashed for indexing disputes (ppm)
     */
    function initialize(
        address _controller,
        address _arbitrator,
        uint256 _minimumDeposit,
        uint32 _fishermanRewardPercentage,
        uint32 _qrySlashingPercentage,
        uint32 _idxSlashingPercentage
    ) external onlyImpl {
        Managed._initialize(_controller);

        // Settings
        _setArbitrator(_arbitrator);
        _setMinimumDeposit(_minimumDeposit);
        _setFishermanRewardPercentage(_fishermanRewardPercentage);
        _setSlashingPercentage(_qrySlashingPercentage, _idxSlashingPercentage);

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
     * @inheritdoc IDisputeManager
     */
    function setArbitrator(address _arbitrator) external override onlyGovernor {
        _setArbitrator(_arbitrator);
    }

    /**
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(_arbitrator != address(0), "Arbitrator must be set");
        arbitrator = _arbitrator;
        emit ParameterUpdated("arbitrator");
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external override onlyGovernor {
        _setMinimumDeposit(_minimumDeposit);
    }

    /**
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function _setMinimumDeposit(uint256 _minimumDeposit) private {
        require(_minimumDeposit > 0, "Minimum deposit must be set");
        minimumDeposit = _minimumDeposit;
        emit ParameterUpdated("minimumDeposit");
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function setFishermanRewardPercentage(uint32 _percentage) external override onlyGovernor {
        _setFishermanRewardPercentage(_percentage);
    }

    /**
     * @notice Set the percent reward that the fisherman gets when slashing occurs.
     * @param _percentage Reward as a percentage of indexer stake
     */
    function _setFishermanRewardPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Reward percentage must be below or equal to MAX_PPM");
        fishermanRewardPercentage = _percentage;
        emit ParameterUpdated("fishermanRewardPercentage");
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function setSlashingPercentage(uint32 _qryPercentage, uint32 _idxPercentage) external override onlyGovernor {
        _setSlashingPercentage(_qryPercentage, _idxPercentage);
    }

    /**
     * @notice Internal: Set the percentage used for slashing indexers.
     * @param _qryPercentage Percentage slashing for query disputes
     * @param _idxPercentage Percentage slashing for indexing disputes
     */
    function _setSlashingPercentage(uint32 _qryPercentage, uint32 _idxPercentage) private {
        // Must be within 0% to 100% (inclusive)
        require(
            _qryPercentage <= MAX_PPM && _idxPercentage <= MAX_PPM,
            "Slashing percentage must be below or equal to MAX_PPM"
        );
        qrySlashingPercentage = _qryPercentage;
        idxSlashingPercentage = _idxPercentage;
        emit ParameterUpdated("qrySlashingPercentage");
        emit ParameterUpdated("idxSlashingPercentage");
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function isDisputeCreated(bytes32 _disputeID) public view override returns (bool) {
        return disputes[_disputeID].status != DisputeStatus.Null;
    }

    /**
     * @inheritdoc IDisputeManager
     * @dev Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     */
    function encodeHashReceipt(Receipt memory _receipt) public view override returns (bytes32) {
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
     * @inheritdoc IDisputeManager
     * @dev Everything must match except for the responseID.
     */
    function areConflictingAttestations(
        Attestation memory _attestation1,
        Attestation memory _attestation2
    ) public pure override returns (bool) {
        return (_attestation1.requestCID == _attestation2.requestCID &&
            _attestation1.subgraphDeploymentID == _attestation2.subgraphDeploymentID &&
            _attestation1.responseCID != _attestation2.responseCID);
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function getAttestationIndexer(Attestation memory _attestation) public view override returns (address) {
        // Get attestation signer. Indexers signs with the allocationID
        address allocationID = _recoverAttestationSigner(_attestation);

        IStaking.Allocation memory alloc = staking().getAllocation(allocationID);
        require(alloc.indexer != address(0), "Indexer cannot be found for the attestation");
        require(
            alloc.subgraphDeploymentID == _attestation.subgraphDeploymentID,
            "Allocation and attestation subgraphDeploymentID must match"
        );
        return alloc.indexer;
    }

    /**
     * @inheritdoc IDisputeManager
     * @dev This function is called by a fisherman that will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     */
    function createQueryDispute(bytes calldata _attestationData, uint256 _deposit) external override returns (bytes32) {
        // Get funds from submitter
        _pullSubmitterDeposit(_deposit);

        // Create a dispute
        return
            _createQueryDisputeWithAttestation(
                msg.sender,
                _deposit,
                _parseAttestation(_attestationData),
                _attestationData
            );
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function createQueryDisputeConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external override returns (bytes32, bytes32) {
        address fisherman = msg.sender;

        // Parse each attestation
        Attestation memory attestation1 = _parseAttestation(_attestationData1);
        Attestation memory attestation2 = _parseAttestation(_attestationData2);

        // Test that attestations are conflicting
        require(areConflictingAttestations(attestation1, attestation2), "Attestations must be in conflict");

        // Create the disputes
        // The deposit is zero for conflicting attestations
        bytes32 dID1 = _createQueryDisputeWithAttestation(fisherman, 0, attestation1, _attestationData1);
        bytes32 dID2 = _createQueryDisputeWithAttestation(fisherman, 0, attestation2, _attestationData2);

        // Store the linked disputes to be resolved
        disputes[dID1].relatedDisputeID = dID2;
        disputes[dID2].relatedDisputeID = dID1;

        // Emit event that links the two created disputes
        emit DisputeLinked(dID1, dID2);

        return (dID1, dID2);
    }

    /**
     * @notice Create a query dispute passing the parsed attestation.
     * To be used in createQueryDispute() and createQueryDisputeConflict()
     * to avoid calling parseAttestation() multiple times
     * `_attestationData` is only passed to be emitted
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _attestation Attestation struct parsed from bytes
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @return DisputeID
     */
    function _createQueryDisputeWithAttestation(
        address _fisherman,
        uint256 _deposit,
        Attestation memory _attestation,
        bytes memory _attestationData
    ) private returns (bytes32) {
        // Get the indexer that signed the attestation
        address indexer = getAttestationIndexer(_attestation);

        // The indexer is disputable
        require(staking().getIndexerStakedTokens(indexer) > 0, "Dispute indexer has no stake");

        // Create a disputeID
        bytes32 disputeID = keccak256(
            abi.encodePacked(
                _attestation.requestCID,
                _attestation.responseCID,
                _attestation.subgraphDeploymentID,
                indexer,
                _fisherman
            )
        );

        // Only one dispute for a (indexer, subgraphDeploymentID) at a time
        require(!isDisputeCreated(disputeID), "Dispute already created");

        // Store dispute
        disputes[disputeID] = Dispute(
            indexer,
            _fisherman,
            _deposit,
            0, // no related dispute,
            DisputeType.QueryDispute,
            IDisputeManager.DisputeStatus.Pending
        );

        emit QueryDisputeCreated(
            disputeID,
            indexer,
            _fisherman,
            _deposit,
            _attestation.subgraphDeploymentID,
            _attestationData
        );

        return disputeID;
    }

    /**
     * @dev Create an indexing dispute for the arbitrator to resolve.
     * The disputes are created in reference to an allocationID
     * This function is called by a challenger that will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     * @inheritdoc IDisputeManager
     */
    function createIndexingDispute(address _allocationID, uint256 _deposit) external override returns (bytes32) {
        // Get funds from submitter
        _pullSubmitterDeposit(_deposit);

        // Create a dispute
        return _createIndexingDisputeWithAllocation(msg.sender, _deposit, _allocationID);
    }

    /**
     * @notice Create indexing dispute internal function.
     * @param _fisherman The challenger creating the dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _allocationID Allocation disputed
     * @return disputeID The ID of the created dispute
     */
    function _createIndexingDisputeWithAllocation(
        address _fisherman,
        uint256 _deposit,
        address _allocationID
    ) private returns (bytes32) {
        // Create a disputeID
        bytes32 disputeID = keccak256(abi.encodePacked(_allocationID));

        // Only one dispute for an allocationID at a time
        require(!isDisputeCreated(disputeID), "Dispute already created");

        // Allocation must exist
        IStaking staking = staking();
        IStaking.Allocation memory alloc = staking.getAllocation(_allocationID);
        require(alloc.indexer != address(0), "Dispute allocation must exist");

        // The indexer must be disputable
        require(staking.getIndexerStakedTokens(alloc.indexer) > 0, "Dispute indexer has no stake");

        // Store dispute
        disputes[disputeID] = Dispute(
            alloc.indexer,
            _fisherman,
            _deposit,
            0,
            DisputeType.IndexingDispute,
            IDisputeManager.DisputeStatus.Pending
        );

        emit IndexingDisputeCreated(disputeID, alloc.indexer, _fisherman, _deposit, _allocationID);

        return disputeID;
    }

    /**
     * @dev This function will revert if the indexer is not slashable, whether because it does not have
     * any stake available or the slashing percentage is configured to be zero. In those cases
     * a dispute must be resolved using drawDispute or rejectDispute.
     * @inheritdoc IDisputeManager
     */
    function acceptDispute(bytes32 _disputeID) external override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // store the dispute status
        dispute.status = IDisputeManager.DisputeStatus.Accepted;

        // Slash
        (, uint256 tokensToReward) = _slashIndexer(dispute.indexer, dispute.fisherman, dispute.disputeType);

        // Give the fisherman their deposit back
        TokenUtils.pushTokens(graphToken(), dispute.fisherman, dispute.deposit);

        if (_isDisputeInConflict(dispute)) {
            rejectDispute(dispute.relatedDisputeID);
        }

        emit DisputeAccepted(_disputeID, dispute.indexer, dispute.fisherman, dispute.deposit.add(tokensToReward));
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function rejectDispute(bytes32 _disputeID) public override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // store dispute status
        dispute.status = IDisputeManager.DisputeStatus.Rejected;

        // Handle conflicting dispute if any
        require(
            !_isDisputeInConflict(dispute),
            "Dispute for conflicting attestation, must accept the related ID to reject"
        );

        // Burn the fisherman's deposit
        TokenUtils.burnTokens(graphToken(), dispute.deposit);

        emit DisputeRejected(_disputeID, dispute.indexer, dispute.fisherman, dispute.deposit);
    }

    /**
     * @inheritdoc IDisputeManager
     */
    function drawDispute(bytes32 _disputeID) external override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // Return deposit to the fisherman
        TokenUtils.pushTokens(graphToken(), dispute.fisherman, dispute.deposit);

        // resolve related dispute if any
        _drawDisputeInConflict(dispute);

        // store dispute status
        dispute.status = IDisputeManager.DisputeStatus.Drawn;

        emit DisputeDrawn(_disputeID, dispute.indexer, dispute.fisherman, dispute.deposit);
    }

    /**
     * @notice Returns whether the dispute is for a conflicting attestation or not.
     * @param _dispute Dispute
     * @return True conflicting attestation dispute
     */
    function _isDisputeInConflict(Dispute memory _dispute) private view returns (bool) {
        bytes32 relatedID = _dispute.relatedDisputeID;
        // this is so the check returns false when rejecting the related dispute.
        return relatedID != 0 && disputes[relatedID].status == IDisputeManager.DisputeStatus.Pending;
    }

    /**
     * @notice Resolve the conflicting dispute if there is any for the one passed to this function.
     * @param _dispute Dispute
     * @return True if resolved
     */
    function _drawDisputeInConflict(Dispute memory _dispute) private returns (bool) {
        if (_isDisputeInConflict(_dispute)) {
            bytes32 relatedDisputeID = _dispute.relatedDisputeID;
            Dispute storage relatedDispute = disputes[relatedDisputeID];
            relatedDispute.status = IDisputeManager.DisputeStatus.Drawn;
            return true;
        }
        return false;
    }

    /**
     * @notice Pull deposit from submitter account.
     * @param _deposit Amount of tokens to deposit
     */
    function _pullSubmitterDeposit(uint256 _deposit) private {
        // Ensure that fisherman has staked at least the minimum amount
        require(_deposit >= minimumDeposit, "Dispute deposit is under minimum required");

        // Transfer tokens to deposit from fisherman to this contract
        TokenUtils.pullTokens(graphToken(), msg.sender, _deposit);
    }

    /**
     * @notice Make the staking contract slash the indexer and reward the challenger.
     * Give the challenger a reward equal to the fishermanRewardPercentage of slashed amount
     * @param _indexer Address of the indexer
     * @param _challenger Address of the challenger
     * @param _disputeType Type of dispute
     * @return slashAmount Dispute slash amount
     * @return rewardsAmount Dispute rewards amount
     */
    function _slashIndexer(
        address _indexer,
        address _challenger,
        DisputeType _disputeType
    ) private returns (uint256 slashAmount, uint256 rewardsAmount) {
        IStaking staking = staking();

        // Get slashable amount for indexer
        uint256 slashableAmount = staking.getIndexerStakedTokens(_indexer); // slashable tokens

        // Get slash amount
        slashAmount = _getSlashingPercentageForDisputeType(_disputeType).mul(slashableAmount).div(MAX_PPM);
        require(slashAmount > 0, "Dispute has zero tokens to slash");

        // Get rewards amount
        rewardsAmount = uint256(fishermanRewardPercentage).mul(slashAmount).div(MAX_PPM);

        // Have staking contract slash the indexer and reward the fisherman
        // Give the fisherman a reward equal to the fishermanRewardPercentage of slashed amount
        staking.slash(_indexer, slashAmount, rewardsAmount, _challenger);
    }

    /**
     * @notice Return the slashing percentage for the dispute type.
     * @param _disputeType Dispute type
     * @return Slashing percentage to use for the dispute type
     */
    function _getSlashingPercentageForDisputeType(DisputeType _disputeType) private view returns (uint256) {
        if (_disputeType == DisputeType.QueryDispute) return uint256(qrySlashingPercentage);
        if (_disputeType == DisputeType.IndexingDispute) return uint256(idxSlashingPercentage);
        return 0;
    }

    /**
     * @notice Recover the signer address of the `_attestation`.
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
        return ECDSA.recover(messageHash, abi.encodePacked(_attestation.r, _attestation.s, _attestation.v));
    }

    /**
     * @notice Get the running network chain ID
     * @return The chain ID
     */
    function _getChainID() private pure returns (uint256) {
        uint256 id;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            id := chainid()
        }
        return id;
    }

    /**
     * @notice Parse the bytes attestation into a struct from `_data`.
     * @param _data The bytes data to parse into an attestation
     * @return Attestation struct
     */
    function _parseAttestation(bytes memory _data) private pure returns (Attestation memory) {
        // Check attestation data length
        require(_data.length == ATTESTATION_SIZE_BYTES, "Attestation must be 161 bytes long");

        // Decode receipt
        (bytes32 requestCID, bytes32 responseCID, bytes32 subgraphDeploymentID) = abi.decode(
            _data,
            (bytes32, bytes32, bytes32)
        );

        // Decode signature
        // Signature is expected to be in the order defined in the Attestation struct
        bytes32 r = _toBytes32(_data, SIG_R_OFFSET);
        bytes32 s = _toBytes32(_data, SIG_S_OFFSET);
        uint8 v = _toUint8(_data, SIG_V_OFFSET);

        return Attestation(requestCID, responseCID, subgraphDeploymentID, r, s, v);
    }

    /**
     * @notice Parse a uint8 from `_bytes` starting at offset `_start`.
     * @param _bytes The bytes array to parse from
     * @param _start The starting offset in the bytes array
     * @return uint8 value
     */
    function _toUint8(bytes memory _bytes, uint256 _start) private pure returns (uint8) {
        require(_bytes.length >= (_start + UINT8_BYTE_LENGTH), "Bytes: out of bounds");
        uint8 tempUint;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    /**
     * @notice Parse a bytes32 from `_bytes` starting at offset `_start`.
     * @param _bytes The bytes array to parse from
     * @param _start The starting offset in the bytes array
     * @return bytes32 value
     */
    function _toBytes32(bytes memory _bytes, uint256 _start) private pure returns (bytes32) {
        require(_bytes.length >= (_start + BYTES32_BYTE_LENGTH), "Bytes: out of bounds");
        bytes32 tempBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
}
