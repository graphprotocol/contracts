// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

import { SubgraphDisputeManagerV1Storage } from "./SubgraphDisputeManagerStorage.sol";
import { ISubgraphDisputeManager } from "./ISubgraphDisputeManager.sol";
import { ISubgraphService } from "../ISubgraphService.sol";

/*
 * @title SubgraphDisputeManager
 * @notice Provides a way to align the incentives of participants by having slashing as deterrent
 * for incorrect behaviour.
 *
 * There are two types of disputes that can be created: Query disputes and Indexing disputes.
 *
 * Query Disputes:
 * Graph nodes receive queries and return responses with signed receipts called attestations.
 * An attestation can be disputed if the consumer thinks the query response was invalid.
 * Service providers use the derived private key for an allocation to sign attestations.
 *
 * Indexing Disputes:
 * Service providers present a Proof of Indexing (POI) when they close allocations to prove
 * they were indexing a subgraph. The Staking contract emits that proof with the format
 * keccak256(serviceProvider.address, POI).
 * Any challenger can dispute the validity of a POI by submitting a dispute to this contract
 * along with a deposit.
 *
 * Arbitration:
 * Disputes can only be accepted, rejected or drawn by the arbitrator role that can be delegated
 * to a EOA or DAO.
 */
contract SubgraphDisputeManager is SubgraphDisputeManagerV1Storage, ISubgraphDisputeManager {
    ISubgraphService private immutable subgraphService;
    IHorizonStaking private immutable staking;
    IGraphToken private immutable graphToken;

    // -- EIP-712  --

    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;
    bytes32 private constant RECEIPT_TYPE_HASH =
        keccak256("Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)");

    // -- Constants --

    // Attestation size is the sum of the receipt (96) + signature (65)
    uint256 private constant ATTESTATION_SIZE_BYTES = RECEIPT_SIZE_BYTES + SIG_SIZE_BYTES;
    uint256 private constant RECEIPT_SIZE_BYTES = 96;

    uint256 private constant SIG_R_LENGTH = 32;
    uint256 private constant SIG_S_LENGTH = 32;
    uint256 private constant SIG_V_LENGTH = 1;
    uint256 private constant SIG_R_OFFSET = RECEIPT_SIZE_BYTES;
    uint256 private constant SIG_S_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH;
    uint256 private constant SIG_V_OFFSET = RECEIPT_SIZE_BYTES + SIG_R_LENGTH + SIG_S_LENGTH;
    uint256 private constant SIG_SIZE_BYTES = SIG_R_LENGTH + SIG_S_LENGTH + SIG_V_LENGTH;

    uint256 private constant UINT8_BYTE_LENGTH = 1;
    uint256 private constant BYTES32_BYTE_LENGTH = 32;

    uint256 private constant MAX_PPM = 1000000; // 100% in parts per million

    // -- Events --

    /// Emitted when a contract parameter has been updated
    event ParameterUpdated(string param);

    /**
     * @dev Emitted when a query dispute is created for `subgraphDeploymentID` and `serviceProvider`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman and `attestation` submitted.
     */
    event QueryDisputeCreated(
        bytes32 indexed disputeID,
        address indexed serviceProvider,
        address indexed fisherman,
        uint256 tokens,
        bytes32 subgraphDeploymentID,
        bytes attestation
    );

    /**
     * @dev Emitted when an indexing dispute is created for `allocationID` and `serviceProvider`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman.
     */
    event IndexingDisputeCreated(
        bytes32 indexed disputeID,
        address indexed serviceProvider,
        address indexed fisherman,
        uint256 tokens,
        address allocationID
    );

    /**
     * @dev Emitted when arbitrator accepts a `disputeID` to `serviceProvider` created by `fisherman`.
     * The event emits the amount `tokens` transferred to the fisherman, the deposit plus reward.
     */
    event DisputeAccepted(
        bytes32 indexed disputeID,
        address indexed serviceProvider,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator rejects a `disputeID` for `serviceProvider` created by `fisherman`.
     * The event emits the amount `tokens` burned from the fisherman deposit.
     */
    event DisputeRejected(
        bytes32 indexed disputeID,
        address indexed serviceProvider,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator draw a `disputeID` for `serviceProvider` created by `fisherman`.
     * The event emits the amount `tokens` used as deposit and returned to the fisherman.
     */
    event DisputeDrawn(
        bytes32 indexed disputeID,
        address indexed serviceProvider,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when two disputes are in conflict to link them.
     * This event will be emitted after each DisputeCreated event is emitted
     * for each of the individual disputes.
     */
    event DisputeLinked(bytes32 indexed disputeID1, bytes32 indexed disputeID2);

    // -- Modifiers --

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

    modifier onlyPendingDispute(bytes32 _disputeID) {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");
        require(
            disputes[_disputeID].status == ISubgraphDisputeManager.DisputeStatus.Pending,
            "Dispute must be pending"
        );
        _;
    }

    modifier onlyFisherman(bytes32 _disputeID) {
        require(isDisputeCreated(_disputeID), "Dispute does not exist");
        require(msg.sender == disputes[_disputeID].fisherman, "Caller is not the Fisherman");
        _;
    }

    // -- Functions --

    /**
     * @dev Initialize this contract.
     * @param _subgraphService Address of subgraph service contract
     * @param _staking Address of staking contract
     * @param _graphToken Address of Graph token contract
     * @param _arbitrator Arbitrator role
     * @param _disputePeriod Dispute period in seconds
     * @param _minimumDeposit Minimum deposit required to create a Dispute
     * @param _fishermanRewardPercentage Percent of slashed funds for fisherman (ppm)
     * @param _maxSlashingPercentage Maximum percentage of serviceProvider stake that can be slashed (ppm)
     */
    constructor(
        ISubgraphService _subgraphService,
        IHorizonStaking _staking,
        IGraphToken _graphToken,
        address _arbitrator,
        uint64 _disputePeriod,
        uint256 _minimumDeposit,
        uint32 _fishermanRewardPercentage,
        uint32 _maxSlashingPercentage
    ) {
        subgraphService = _subgraphService;
        staking = _staking;
        graphToken = _graphToken;

        // Settings
        _setArbitrator(_arbitrator);
        _setDisputePeriod(_disputePeriod);
        _setMinimumDeposit(_minimumDeposit);
        _setFishermanRewardPercentage(_fishermanRewardPercentage);
        _setMaxSlashingPercentage(_maxSlashingPercentage);

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
     * @dev Set the arbitrator address.
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external override {
        // TODO: onlyGovernor
        _setArbitrator(_arbitrator);
    }

    /**
     * @dev Internal: Set the arbitrator address.
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(_arbitrator != address(0), "Arbitrator must be set");
        arbitrator = _arbitrator;
        emit ParameterUpdated("arbitrator");
    }

    /**
     * @dev Set the dispute period.
     * @notice Update the dispute period to `_disputePeriod` in seconds
     * @param _disputePeriod Dispute period in seconds
     */
    function setDisputePeriod(uint64 _disputePeriod) external override {
        _setDisputePeriod(_disputePeriod);
    }

    /**
     * @dev Internal: Set the dispute period.
     * @notice Update the dispute period to `_disputePeriod` in seconds
     * @param _disputePeriod Dispute period in seconds
     */
    function _setDisputePeriod(uint64 _disputePeriod) private {
        require(_disputePeriod > 0, "Dispute period must be set");
        disputePeriod = _disputePeriod;
        emit ParameterUpdated("disputePeriod");
    }

    /**
     * @dev Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external override {
        // TODO: onlyGovernor
        _setMinimumDeposit(_minimumDeposit);
    }

    /**
     * @dev Internal: Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function _setMinimumDeposit(uint256 _minimumDeposit) private {
        require(_minimumDeposit > 0, "Minimum deposit must be set");
        minimumDeposit = _minimumDeposit;
        emit ParameterUpdated("minimumDeposit");
    }

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of serviceProvider stake
     */
    function setFishermanRewardPercentage(uint32 _percentage) external override {
        // TODO: onlyGovernor
        _setFishermanRewardPercentage(_percentage);
    }

    /**
     * @dev Internal: Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of serviceProvider stake
     */
    function _setFishermanRewardPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_percentage <= MAX_PPM, "Reward percentage must be below or equal to MAX_PPM");
        fishermanRewardPercentage = _percentage;
        emit ParameterUpdated("fishermanRewardPercentage");
    }

    /**
     * @dev Set the maximum percentage that can be used for slashing service providers.
     * @param _maxSlashingPercentage Max percentage slashing for disputes
     */
    function setMaxSlashingPercentage(uint32 _maxSlashingPercentage) external override {
        // TODO: onlyGovernor
        _setMaxSlashingPercentage(_maxSlashingPercentage);
    }

    /**
     * @dev Internal: Set the maximum percentage that can be used for slashing service providers.
     * @param _maxSlashingPercentage Max percentage slashing for disputes
     */
    function _setMaxSlashingPercentage(uint32 _maxSlashingPercentage) private {
        // Must be within 0% to 100% (inclusive)
        require(_maxSlashingPercentage <= MAX_PPM, "Maximum slashing percentage must be below or equal to MAX_PPM");
        maxSlashingPercentage = _maxSlashingPercentage;
        emit ParameterUpdated("maxSlashingPercentage");
    }

    /**
     * @dev Get the verifier cut.
     * @return Verifier cut in percentage (ppm)
     */
    function getVerifierCut() external view returns (uint256) {
        return fishermanRewardPercentage;
    }

    /**
     * @dev Get the dispute period.
     * @return Dispute period in seconds
     */
    function getDisputePeriod() external view returns (uint64) {
        return disputePeriod;
    }

    /**
     * @dev Return whether a dispute exists or not.
     * @notice Return if dispute with ID `_disputeID` exists
     * @param _disputeID True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeID) public view override returns (bool) {
        return disputes[_disputeID].status != DisputeStatus.Null;
    }

    /**
     * @dev Get the message hash that a service provider used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @notice Return the message hash used to sign the receipt
     * @param _receipt Receipt returned by service provider and submitted by fisherman
     * @return Message hash used to sign the receipt
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
     * @dev Returns if two attestations are conflicting.
     * Everything must match except for the responseID.
     * @param _attestation1 Attestation
     * @param _attestation2 Attestation
     * @return True if the two attestations are conflicting
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
     * @dev Returns the serviceProvider that signed an attestation.
     * @param _attestation Attestation
     * @return serviceProvider address
     */
    function getAttestationServiceProvider(Attestation memory _attestation) public view override returns (address) {
        // Get attestation signer. Service providers signs with the allocationID
        address allocationID = _recoverAttestationSigner(_attestation);

        ISubgraphService.Allocation memory alloc = subgraphService.getAllocation(allocationID);
        require(alloc.serviceProvider != address(0), "serviceProvider cannot be found for the attestation");
        require(
            alloc.subgraphDeploymentID == _attestation.subgraphDeploymentID,
            "Allocation and attestation subgraphDeploymentID must match"
        );
        return alloc.serviceProvider;
    }

    /**
     * @dev Create a query dispute for the arbitrator to resolve.
     * This function is called by a fisherman that will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @param _deposit Amount of tokens staked as deposit
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
     * @dev Create query disputes for two conflicting attestations.
     * A conflicting attestation is a proof presented by two different service providers
     * where for the same request on a subgraph the response is different.
     * For this type of dispute the submitter is not required to present a deposit
     * as one of the attestation is considered to be right.
     * Two linked disputes will be created and if the arbitrator resolve one, the other
     * one will be automatically resolved.
     * @param _attestationData1 First attestation data submitted
     * @param _attestationData2 Second attestation data submitted
     * @return DisputeID1, DisputeID2
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
     * @dev Create a query dispute passing the parsed attestation.
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
        // Get the serviceProvider that signed the attestation
        address serviceProvider = getAttestationServiceProvider(_attestation);

        // The serviceProvider is disputable
        IHorizonStaking.Provision memory provision = staking.getProvision(serviceProvider, address(subgraphService));
        require(provision.tokens > 0, "Dispute serviceProvider has no stake");

        // Create a disputeID
        bytes32 disputeID = keccak256(
            abi.encodePacked(
                _attestation.requestCID,
                _attestation.responseCID,
                _attestation.subgraphDeploymentID,
                serviceProvider,
                _fisherman
            )
        );

        // Only one dispute for a (serviceProvider, subgraphDeploymentID) at a time
        require(!isDisputeCreated(disputeID), "Dispute already created");

        // Store dispute
        disputes[disputeID] = Dispute(
            serviceProvider,
            _fisherman,
            _deposit,
            0, // no related dispute,
            DisputeType.QueryDispute,
            ISubgraphDisputeManager.DisputeStatus.Pending,
            block.timestamp
        );

        emit QueryDisputeCreated(
            disputeID,
            serviceProvider,
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
     * @param _allocationID The allocation to dispute
     * @param _deposit Amount of tokens staked as deposit
     */
    function createIndexingDispute(address _allocationID, uint256 _deposit) external override returns (bytes32) {
        // Get funds from submitter
        _pullSubmitterDeposit(_deposit);

        // Create a dispute
        return _createIndexingDisputeWithAllocation(msg.sender, _deposit, _allocationID);
    }

    /**
     * @dev Create indexing dispute internal function.
     * @param _fisherman The challenger creating the dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _allocationID Allocation disputed
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
        // TODO: Check ISubgraphService for Allocation
        // TODO: Check ISubgraphService for getAllocation(...)
        ISubgraphService.Allocation memory alloc = subgraphService.getAllocation(_allocationID);
        address serviceProvider = alloc.serviceProvider;
        require(serviceProvider != address(0), "Dispute allocation must exist");

        // The serviceProvider must be disputable
        // TODO: Check ISubgraphService for getServiceProviderStakedTokens(...)
        IHorizonStaking.Provision memory provision = staking.getProvision(serviceProvider, address(subgraphService));
        require(provision.tokens > 0, "Dispute serviceProvider has no stake");

        // Store dispute
        disputes[disputeID] = Dispute(
            alloc.serviceProvider,
            _fisherman,
            _deposit,
            0,
            DisputeType.IndexingDispute,
            ISubgraphDisputeManager.DisputeStatus.Pending,
            block.timestamp
        );

        emit IndexingDisputeCreated(disputeID, alloc.serviceProvider, _fisherman, _deposit, _allocationID);

        return disputeID;
    }

    /**
     * @dev The arbitrator accepts a dispute as being valid.
     * This function will revert if the service provider is not slashable, whether because it does not have
     * any stake available or the slashing percentage is configured to be zero. In those cases
     * a dispute must be resolved using drawDispute or rejectDispute.
     * @notice Accept a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be accepted
     * @param _slashAmount Amount of tokens to slash from the service provider
     */
    function acceptDispute(
        bytes32 _disputeID,
        uint256 _slashAmount
    ) external override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // store the dispute status
        dispute.status = ISubgraphDisputeManager.DisputeStatus.Accepted;

        // Slash
        uint256 tokensToReward = _slashServiceProvider(dispute.serviceProvider, _slashAmount);

        // Give the fisherman their reward and their deposit back
        TokenUtils.pushTokens(graphToken, dispute.fisherman, tokensToReward + dispute.deposit);

        if (_isDisputeInConflict(dispute)) {
            rejectDispute(dispute.relatedDisputeID);
        }

        emit DisputeAccepted(_disputeID, dispute.serviceProvider, dispute.fisherman, dispute.deposit + tokensToReward);
    }

    /**
     * @dev The arbitrator rejects a dispute as being invalid.
     * @notice Reject a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be rejected
     */
    function rejectDispute(bytes32 _disputeID) public override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // store dispute status
        dispute.status = ISubgraphDisputeManager.DisputeStatus.Rejected;

        // Handle conflicting dispute if any
        require(
            !_isDisputeInConflict(dispute),
            "Dispute for conflicting attestation, must accept the related ID to reject"
        );

        // Burn the fisherman's deposit
        TokenUtils.burnTokens(graphToken, dispute.deposit);

        emit DisputeRejected(_disputeID, dispute.serviceProvider, dispute.fisherman, dispute.deposit);
    }

    /**
     * @dev The arbitrator draws dispute.
     * @notice Ignore a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be disregarded
     */
    function drawDispute(bytes32 _disputeID) public override onlyArbitrator onlyPendingDispute(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];

        // Return deposit to the fisherman
        TokenUtils.pushTokens(graphToken, dispute.fisherman, dispute.deposit);

        // resolve related dispute if any
        _drawDisputeInConflict(dispute);

        // store dispute status
        dispute.status = ISubgraphDisputeManager.DisputeStatus.Drawn;

        emit DisputeDrawn(_disputeID, dispute.serviceProvider, dispute.fisherman, dispute.deposit);
    }

    /**
     * @dev Once the dispute period ends, if the disput status remains Pending,
     * the fisherman can cancel the dispute and get back their initial deposit.
     * @notice Cancel a dispute with ID `_disputeID`
     * @param _disputeID ID of the dispute to be cancelled
     */
    function cancelDispute(bytes32 _disputeID) external override onlyFisherman(_disputeID) {
        Dispute storage dispute = disputes[_disputeID];
        require(dispute.status == ISubgraphDisputeManager.DisputeStatus.Pending, "Dispute must be pending");
        // Check if dispute period has finished
        require(block.timestamp > dispute.createdAt + disputePeriod, "Dispute period has not finished");

        // Return deposit to the fisherman
        TokenUtils.pushTokens(graphToken, dispute.fisherman, dispute.deposit);

        // resolve related dispute if any
        _cancelDisputeInConflict(dispute);

        // store dispute status
        dispute.status = ISubgraphDisputeManager.DisputeStatus.Cancelled;
    }

    /**
     * @dev Returns whether the dispute is for a conflicting attestation or not.
     * @param _dispute Dispute
     * @return True conflicting attestation dispute
     */
    function _isDisputeInConflict(Dispute memory _dispute) private view returns (bool) {
        bytes32 relatedID = _dispute.relatedDisputeID;
        // this is so the check returns false when rejecting the related dispute.
        return relatedID != 0 && disputes[relatedID].status == ISubgraphDisputeManager.DisputeStatus.Pending;
    }

    /**
     * @dev Resolve the conflicting dispute if there is any for the one passed to this function.
     * @param _dispute Dispute
     * @return True if resolved
     */
    function _drawDisputeInConflict(Dispute memory _dispute) private returns (bool) {
        if (_isDisputeInConflict(_dispute)) {
            bytes32 relatedDisputeID = _dispute.relatedDisputeID;
            Dispute storage relatedDispute = disputes[relatedDisputeID];
            relatedDispute.status = ISubgraphDisputeManager.DisputeStatus.Drawn;
            return true;
        }
        return false;
    }

    /**
     * @dev Cancel the conflicting dispute if there is any for the one passed to this function.
     * @param _dispute Dispute
     * @return True if cancelled
     */
    function _cancelDisputeInConflict(Dispute memory _dispute) private returns (bool) {
        if (_isDisputeInConflict(_dispute)) {
            bytes32 relatedDisputeID = _dispute.relatedDisputeID;
            Dispute storage relatedDispute = disputes[relatedDisputeID];
            relatedDispute.status = ISubgraphDisputeManager.DisputeStatus.Cancelled;
            return true;
        }
        return false;
    }

    /**
     * @dev Pull deposit from submitter account.
     * @param _deposit Amount of tokens to deposit
     */
    function _pullSubmitterDeposit(uint256 _deposit) private {
        // Ensure that fisherman has staked at least the minimum amount
        require(_deposit >= minimumDeposit, "Dispute deposit is under minimum required");

        // Transfer tokens to deposit from fisherman to this contract
        TokenUtils.pullTokens(graphToken, msg.sender, _deposit);
    }

    /**
     * @dev Make the subgraph service contract slash the service provider and reward the challenger.
     * Give the challenger a reward equal to the fishermanRewardPercentage of slashed amount
     * @param _serviceProvider Address of the service provider
     * @param _slashAmount Amount of tokens to slash from the service provider
     */
    function _slashServiceProvider(
        address _serviceProvider,
        uint256 _slashAmount
    ) private returns (uint256 rewardsAmount) {
        // Get slashable amount for serviceProvider
        IHorizonStaking.Provision memory provision = staking.getProvision(_serviceProvider, address(subgraphService));
        uint256 totalProvisionTokens = provision.tokens + provision.delegatedTokens; // slashable tokens

        // Get slash amount
        uint256 maxSlashAmount = (maxSlashingPercentage * totalProvisionTokens) / MAX_PPM;
        require(_slashAmount > 0, "Dispute has zero tokens to slash");
        require(_slashAmount <= maxSlashAmount, "Slash amount exceeds maximum slashable amount");

        // Rewards amount can only be extracted from service poriver tokens so
        // we grab the minimum between the slash amount and service provider's tokens
        uint256 maxRewardableTokens = Math.min(_slashAmount, provision.tokens);
        rewardsAmount = (fishermanRewardPercentage * maxRewardableTokens) / MAX_PPM;

        subgraphService.slash(_serviceProvider, _slashAmount, rewardsAmount);
        return rewardsAmount;
    }

    /**
     * @dev Recover the signer address of the `_attestation`.
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
        // NOTE: The signer of the attestation is the service provider that served the request
        return ECDSA.recover(messageHash, abi.encodePacked(_attestation.r, _attestation.s, _attestation.v));
    }

    /**
     * @dev Get the running network chain ID
     * @return The chain ID
     */
    function _getChainID() private view returns (uint256) {
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
     * @dev Parse a uint8 from `_bytes` starting at offset `_start`.
     * @return uint8 value
     */
    function _toUint8(bytes memory _bytes, uint256 _start) private pure returns (uint8) {
        require(_bytes.length >= (_start + UINT8_BYTE_LENGTH), "Bytes: out of bounds");
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
    function _toBytes32(bytes memory _bytes, uint256 _start) private pure returns (bytes32) {
        require(_bytes.length >= (_start + BYTES32_BYTE_LENGTH), "Bytes: out of bounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }
}
