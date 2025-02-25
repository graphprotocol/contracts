// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStaking } from "@graphprotocol/horizon/contracts/interfaces/IHorizonStaking.sol";
import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { PPMMath } from "@graphprotocol/horizon/contracts/libraries/PPMMath.sol";
import { MathUtils } from "@graphprotocol/horizon/contracts/libraries/MathUtils.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { Attestation } from "./libraries/Attestation.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GraphDirectory } from "@graphprotocol/horizon/contracts/utilities/GraphDirectory.sol";
import { DisputeManagerV1Storage } from "./DisputeManagerStorage.sol";
import { AttestationManager } from "./utilities/AttestationManager.sol";

/**
 * @title DisputeManager
 * @notice Provides a way to permissionlessly create disputes for incorrect behavior in the Subgraph Service.
 *
 * There are two types of disputes that can be created: Query disputes and Indexing disputes.
 *
 * Query Disputes:
 * Graph nodes receive queries and return responses with signed receipts called attestations.
 * An attestation can be disputed if the consumer thinks the query response was invalid.
 * Indexers use the derived private key for an allocation to sign attestations.
 *
 * Indexing Disputes:
 * Indexers periodically present a Proof of Indexing (POI) to prove they are indexing a subgraph.
 * The Subgraph Service contract emits that proof which includes the POI. Any fisherman can dispute the
 * validity of a POI by submitting a dispute to this contract along with a deposit.
 *
 * Arbitration:
 * Disputes can only be accepted, rejected or drawn by the arbitrator role that can be delegated
 * to a EOA or DAO.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract DisputeManager is
    Initializable,
    OwnableUpgradeable,
    GraphDirectory,
    AttestationManager,
    DisputeManagerV1Storage,
    IDisputeManager
{
    using TokenUtils for IGraphToken;
    using PPMMath for uint256;

    // -- Constants --

    // Maximum value for fisherman reward cut in PPM
    uint32 public constant MAX_FISHERMAN_REWARD_CUT = 500000;

    // Minimum value for dispute deposit
    uint256 public constant MIN_DISPUTE_DEPOSIT = 1e18; // 1 GRT

    // -- Modifiers --

    /**
     * @notice Check if the caller is the arbitrator.
     */
    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, DisputeManagerNotArbitrator());
        _;
    }

    /**
     * @notice Check if the dispute exists and is pending.
     * @param disputeId The dispute Id
     */
    modifier onlyPendingDispute(bytes32 disputeId) {
        require(isDisputeCreated(disputeId), DisputeManagerInvalidDispute(disputeId));
        require(
            disputes[disputeId].status == IDisputeManager.DisputeStatus.Pending,
            DisputeManagerDisputeNotPending(disputes[disputeId].status)
        );
        _;
    }

    /**
     * @notice Check if the caller is the fisherman of the dispute.
     * @param disputeId The dispute Id
     */
    modifier onlyFisherman(bytes32 disputeId) {
        require(isDisputeCreated(disputeId), DisputeManagerInvalidDispute(disputeId));
        require(msg.sender == disputes[disputeId].fisherman, DisputeManagerNotFisherman());
        _;
    }

    /**
     * @notice Contract constructor
     * @param controller Address of the controller
     */
    constructor(address controller) GraphDirectory(controller) {
        _disableInitializers();
    }

    /**
     * @notice Initialize this contract.
     * @param owner The owner of the contract
     * @param arbitrator Arbitrator role
     * @param disputePeriod Dispute period in seconds
     * @param disputeDeposit Deposit required to create a Dispute
     * @param fishermanRewardCut_ Percent of slashed funds for fisherman (ppm)
     * @param maxSlashingCut_ Maximum percentage of indexer stake that can be slashed (ppm)
     */
    function initialize(
        address owner,
        address arbitrator,
        uint64 disputePeriod,
        uint256 disputeDeposit,
        uint32 fishermanRewardCut_,
        uint32 maxSlashingCut_
    ) external initializer {
        __Ownable_init(owner);
        __AttestationManager_init();

        _setArbitrator(arbitrator);
        _setDisputePeriod(disputePeriod);
        _setDisputeDeposit(disputeDeposit);
        _setFishermanRewardCut(fishermanRewardCut_);
        _setMaxSlashingCut(maxSlashingCut_);
    }

    /**
     * @notice Create an indexing dispute for the arbitrator to resolve.
     * The disputes are created in reference to an allocationId and specifically
     * a POI for that allocation.
     * This function is called by a fisherman and it will pull `disputeDeposit` GRT tokens.
     *
     * Requirements:
     * - fisherman must have previously approved this contract to pull `disputeDeposit` amount
     *   of tokens from their balance.
     *
     * @param allocationId The allocation to dispute
     * @param poi The Proof of Indexing (POI) being disputed
     */
    function createIndexingDispute(address allocationId, bytes32 poi) external override returns (bytes32) {
        // Get funds from fisherman
        _graphToken().pullTokens(msg.sender, disputeDeposit);

        // Create a dispute
        return _createIndexingDisputeWithAllocation(msg.sender, disputeDeposit, allocationId, poi);
    }

    /**
     * @notice Create a query dispute for the arbitrator to resolve.
     * This function is called by a fisherman and it will pull `disputeDeposit` GRT tokens.
     *
     * * Requirements:
     * - fisherman must have previously approved this contract to pull `disputeDeposit` amount
     *   of tokens from their balance.
     *
     * @param attestationData Attestation bytes submitted by the fisherman
     */
    function createQueryDispute(bytes calldata attestationData) external override returns (bytes32) {
        // Get funds from fisherman
        _graphToken().pullTokens(msg.sender, disputeDeposit);

        // Create a dispute
        return
            _createQueryDisputeWithAttestation(
                msg.sender,
                disputeDeposit,
                Attestation.parse(attestationData),
                attestationData
            );
    }

    /**
     * @notice Create query disputes for two conflicting attestations.
     * A conflicting attestation is a proof presented by two different indexers
     * where for the same request on a subgraph the response is different.
     * Two linked disputes will be created and if the arbitrator resolve one, the other
     * one will be automatically resolved. Note that:
     * - it's not possible to reject a conflicting query dispute as by definition at least one
     * of the attestations is incorrect.
     * - if both attestations are proven to be incorrect, the arbitrator can slash the indexer twice.
     * Requirements:
     * - fisherman must have previously approved this contract to pull `disputeDeposit` amount
     *   of tokens from their balance.
     * @param attestationData1 First attestation data submitted
     * @param attestationData2 Second attestation data submitted
     * @return DisputeId1, DisputeId2
     */
    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external override returns (bytes32, bytes32) {
        address fisherman = msg.sender;

        // Parse each attestation
        Attestation.State memory attestation1 = Attestation.parse(attestationData1);
        Attestation.State memory attestation2 = Attestation.parse(attestationData2);

        // Test that attestations are conflicting
        require(
            Attestation.areConflicting(attestation1, attestation2),
            DisputeManagerNonConflictingAttestations(
                attestation1.requestCID,
                attestation1.responseCID,
                attestation1.subgraphDeploymentId,
                attestation2.requestCID,
                attestation2.responseCID,
                attestation2.subgraphDeploymentId
            )
        );

        // Get funds from fisherman
        _graphToken().pullTokens(msg.sender, disputeDeposit);

        // Create the disputes
        // The deposit is zero for conflicting attestations
        bytes32 dId1 = _createQueryDisputeWithAttestation(
            fisherman,
            disputeDeposit / 2,
            attestation1,
            attestationData1
        );
        bytes32 dId2 = _createQueryDisputeWithAttestation(
            fisherman,
            disputeDeposit / 2,
            attestation2,
            attestationData2
        );

        // Store the linked disputes to be resolved
        disputes[dId1].relatedDisputeId = dId2;
        disputes[dId2].relatedDisputeId = dId1;

        // Emit event that links the two created disputes
        emit DisputeLinked(dId1, dId2);

        return (dId1, dId2);
    }

    /**
     * @notice The arbitrator accepts a dispute as being valid.
     * This function will revert if the indexer is not slashable, whether because it does not have
     * any stake available or the slashing percentage is configured to be zero. In those cases
     * a dispute must be resolved using drawDispute or rejectDispute.
     * This function will also revert if the dispute is in conflict, to accept a conflicting dispute
     * use acceptDisputeConflict.
     * @dev Accept a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be accepted
     * @param tokensSlash Amount of tokens to slash from the indexer
     */
    function acceptDispute(
        bytes32 disputeId,
        uint256 tokensSlash
    ) external override onlyArbitrator onlyPendingDispute(disputeId) {
        require(!_isDisputeInConflict(disputes[disputeId]), DisputeManagerDisputeInConflict(disputeId));
        Dispute storage dispute = disputes[disputeId];
        _acceptDispute(disputeId, dispute, tokensSlash);
    }

    /**
     * @notice The arbitrator accepts a conflicting dispute as being valid.
     * This function will revert if the indexer is not slashable, whether because it does not have
     * any stake available or the slashing percentage is configured to be zero. In those cases
     * a dispute must be resolved using drawDispute.
     * @param disputeId Id of the dispute to be accepted
     * @param tokensSlash Amount of tokens to slash from the indexer for the first dispute
     * @param acceptDisputeInConflict Accept the conflicting dispute. Otherwise it will be drawn automatically
     * @param tokensSlashRelated Amount of tokens to slash from the indexer for the related dispute in case
     * acceptDisputeInConflict is true, otherwise it will be ignored
     */
    function acceptDisputeConflict(
        bytes32 disputeId,
        uint256 tokensSlash,
        bool acceptDisputeInConflict,
        uint256 tokensSlashRelated
    ) external override onlyArbitrator onlyPendingDispute(disputeId) {
        require(_isDisputeInConflict(disputes[disputeId]), DisputeManagerDisputeNotInConflict(disputeId));
        Dispute storage dispute = disputes[disputeId];
        _acceptDispute(disputeId, dispute, tokensSlash);

        if (acceptDisputeInConflict) {
            _acceptDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId], tokensSlashRelated);
        } else {
            _drawDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId]);
        }
    }

    /**
     * @notice The arbitrator rejects a dispute as being invalid.
     * Note that conflicting query disputes cannot be rejected.
     * @dev Reject a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be rejected
     */
    function rejectDispute(bytes32 disputeId) external override onlyArbitrator onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        require(!_isDisputeInConflict(dispute), DisputeManagerDisputeInConflict(disputeId));
        _rejectDispute(disputeId, dispute);
    }

    /**
     * @notice The arbitrator draws dispute.
     * Note that drawing a conflicting query dispute should not be possible however it is allowed
     * to give arbitrators greater flexibility when resolving disputes.
     * @dev Ignore a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be disregarded
     */
    function drawDispute(bytes32 disputeId) external override onlyArbitrator onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        _drawDispute(disputeId, dispute);

        if (_isDisputeInConflict(dispute)) {
            _drawDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId]);
        }
    }

    /**
     * @notice Once the dispute period ends, if the dispute status remains Pending,
     * the fisherman can cancel the dispute and get back their initial deposit.
     * Note that cancelling a conflicting query dispute will also cancel the related dispute.
     * @dev Cancel a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be cancelled
     */
    function cancelDispute(bytes32 disputeId) external override onlyFisherman(disputeId) onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];

        // Check if dispute period has finished
        require(dispute.createdAt + disputePeriod < block.timestamp, DisputeManagerDisputePeriodNotFinished());
        _cancelDispute(disputeId, dispute);

        if (_isDisputeInConflict(dispute)) {
            _cancelDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId]);
        }
    }

    /**
     * @notice Set the arbitrator address.
     * @dev Update the arbitrator to `_arbitrator`
     * @param arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address arbitrator) external override onlyOwner {
        _setArbitrator(arbitrator);
    }

    /**
     * @notice Set the dispute period.
     * @dev Update the dispute period to `_disputePeriod` in seconds
     * @param disputePeriod Dispute period in seconds
     */
    function setDisputePeriod(uint64 disputePeriod) external override onlyOwner {
        _setDisputePeriod(disputePeriod);
    }

    /**
     * @notice Set the dispute deposit required to create a dispute.
     * @dev Update the dispute deposit to `_disputeDeposit` Graph Tokens
     * @param disputeDeposit The dispute deposit in Graph Tokens
     */
    function setDisputeDeposit(uint256 disputeDeposit) external override onlyOwner {
        _setDisputeDeposit(disputeDeposit);
    }

    /**
     * @notice Set the percent reward that the fisherman gets when slashing occurs.
     * @dev Update the reward percentage to `_percentage`
     * @param fishermanRewardCut_ Reward as a percentage of indexer stake
     */
    function setFishermanRewardCut(uint32 fishermanRewardCut_) external override onlyOwner {
        _setFishermanRewardCut(fishermanRewardCut_);
    }

    /**
     * @notice Set the maximum percentage that can be used for slashing indexers.
     * @param maxSlashingCut_ Max percentage slashing for disputes
     */
    function setMaxSlashingCut(uint32 maxSlashingCut_) external override onlyOwner {
        _setMaxSlashingCut(maxSlashingCut_);
    }

    /**
     * @notice Set the subgraph service address.
     * @dev Update the subgraph service to `_subgraphService`
     * @param subgraphService The address of the subgraph service contract
     */
    function setSubgraphService(address subgraphService) external override onlyOwner {
        _setSubgraphService(subgraphService);
    }

    /**
     * @notice Get the message hash that a indexer used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @dev Return the message hash used to sign the receipt
     * @param receipt Receipt returned by indexer and submitted by fisherman
     * @return Message hash used to sign the receipt
     */
    function encodeReceipt(Attestation.Receipt memory receipt) external view override returns (bytes32) {
        return _encodeReceipt(receipt);
    }

    /**
     * @notice Get the verifier cut.
     * @return Verifier cut in percentage (ppm)
     */
    function getVerifierCut() external view override returns (uint32) {
        return fishermanRewardCut;
    }

    /**
     * @notice Get the dispute period.
     * @return Dispute period in seconds
     */
    function getDisputePeriod() external view override returns (uint64) {
        return disputePeriod;
    }

    /**
     * @notice Get the stake snapshot for an indexer.
     * @param indexer The indexer address
     */
    function getStakeSnapshot(address indexer) external view override returns (uint256) {
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(
            indexer,
            address(_getSubgraphService())
        );
        return _getStakeSnapshot(indexer, provision.tokens);
    }

    /**
     * @notice Checks if two attestations are conflicting.
     * @param attestation1 The first attestation
     * @param attestation2 The second attestation
     */
    function areConflictingAttestations(
        Attestation.State memory attestation1,
        Attestation.State memory attestation2
    ) external pure override returns (bool) {
        return Attestation.areConflicting(attestation1, attestation2);
    }

    /**
     * @notice Returns the indexer that signed an attestation.
     * @param attestation Attestation
     * @return indexer address
     */
    function getAttestationIndexer(Attestation.State memory attestation) public view returns (address) {
        // Get attestation signer. Indexers signs with the allocationId
        address allocationId = _recoverSigner(attestation);

        Allocation.State memory alloc = _getSubgraphService().getAllocation(allocationId);
        require(alloc.indexer != address(0), DisputeManagerIndexerNotFound(allocationId));
        require(
            alloc.subgraphDeploymentId == attestation.subgraphDeploymentId,
            DisputeManagerNonMatchingSubgraphDeployment(alloc.subgraphDeploymentId, attestation.subgraphDeploymentId)
        );
        return alloc.indexer;
    }

    /**
     * @notice Return whether a dispute exists or not.
     * @dev Return if dispute with Id `disputeId` exists
     * @param disputeId True if dispute already exists
     */
    function isDisputeCreated(bytes32 disputeId) public view override returns (bool) {
        return disputes[disputeId].status != DisputeStatus.Null;
    }

    /**
     * @notice Create a query dispute passing the parsed attestation.
     * To be used in createQueryDispute() and createQueryDisputeConflict()
     * to avoid calling parseAttestation() multiple times
     * `attestationData` is only passed to be emitted
     * @param _fisherman Creator of dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _attestation Attestation struct parsed from bytes
     * @param _attestationData Attestation bytes submitted by the fisherman
     * @return DisputeId
     */
    function _createQueryDisputeWithAttestation(
        address _fisherman,
        uint256 _deposit,
        Attestation.State memory _attestation,
        bytes memory _attestationData
    ) private returns (bytes32) {
        // Get the indexer that signed the attestation
        address indexer = getAttestationIndexer(_attestation);

        // The indexer is disputable
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(
            indexer,
            address(_getSubgraphService())
        );
        require(provision.tokens != 0, DisputeManagerZeroTokens());

        // Create a disputeId
        bytes32 disputeId = keccak256(
            abi.encodePacked(
                _attestation.requestCID,
                _attestation.responseCID,
                _attestation.subgraphDeploymentId,
                indexer,
                _fisherman
            )
        );

        // Only one dispute for a (indexer, subgraphDeploymentId) at a time
        require(!isDisputeCreated(disputeId), DisputeManagerDisputeAlreadyCreated(disputeId));

        // Store dispute
        uint256 stakeSnapshot = _getStakeSnapshot(indexer, provision.tokens);
        disputes[disputeId] = Dispute(
            indexer,
            _fisherman,
            _deposit,
            0, // no related dispute,
            DisputeType.QueryDispute,
            IDisputeManager.DisputeStatus.Pending,
            block.timestamp,
            stakeSnapshot
        );

        emit QueryDisputeCreated(
            disputeId,
            indexer,
            _fisherman,
            _deposit,
            _attestation.subgraphDeploymentId,
            _attestationData,
            stakeSnapshot
        );

        return disputeId;
    }

    /**
     * @notice Create indexing dispute internal function.
     * @param _fisherman The fisherman creating the dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _allocationId Allocation disputed
     * @param _poi The POI being disputed
     */
    function _createIndexingDisputeWithAllocation(
        address _fisherman,
        uint256 _deposit,
        address _allocationId,
        bytes32 _poi
    ) private returns (bytes32) {
        // Create a disputeId
        bytes32 disputeId = keccak256(abi.encodePacked(_allocationId, _poi));

        // Only one dispute for an allocationId at a time
        require(!isDisputeCreated(disputeId), DisputeManagerDisputeAlreadyCreated(disputeId));

        // Allocation must exist
        ISubgraphService subgraphService_ = _getSubgraphService();
        Allocation.State memory alloc = subgraphService_.getAllocation(_allocationId);
        address indexer = alloc.indexer;
        require(indexer != address(0), DisputeManagerIndexerNotFound(_allocationId));

        // The indexer must be disputable
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(indexer, address(subgraphService_));
        require(provision.tokens != 0, DisputeManagerZeroTokens());

        // Store dispute
        uint256 stakeSnapshot = _getStakeSnapshot(indexer, provision.tokens);
        disputes[disputeId] = Dispute(
            alloc.indexer,
            _fisherman,
            _deposit,
            0,
            DisputeType.IndexingDispute,
            IDisputeManager.DisputeStatus.Pending,
            block.timestamp,
            stakeSnapshot
        );

        emit IndexingDisputeCreated(disputeId, alloc.indexer, _fisherman, _deposit, _allocationId, _poi, stakeSnapshot);

        return disputeId;
    }

    function _acceptDispute(bytes32 _disputeId, Dispute storage _dispute, uint256 _tokensSlashed) private {
        uint256 tokensToReward = _slashIndexer(_dispute.indexer, _tokensSlashed, _dispute.stakeSnapshot);
        _dispute.status = IDisputeManager.DisputeStatus.Accepted;
        _graphToken().pushTokens(_dispute.fisherman, tokensToReward + _dispute.deposit);

        emit DisputeAccepted(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit + tokensToReward);
    }

    function _rejectDispute(bytes32 _disputeId, Dispute storage _dispute) private {
        _dispute.status = IDisputeManager.DisputeStatus.Rejected;
        _graphToken().burnTokens(_dispute.deposit);

        emit DisputeRejected(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit);
    }

    function _drawDispute(bytes32 _disputeId, Dispute storage _dispute) private {
        _dispute.status = IDisputeManager.DisputeStatus.Drawn;
        _graphToken().pushTokens(_dispute.fisherman, _dispute.deposit);

        emit DisputeDrawn(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit);
    }

    function _cancelDispute(bytes32 _disputeId, Dispute storage _dispute) private {
        _dispute.status = IDisputeManager.DisputeStatus.Cancelled;
        _graphToken().pushTokens(_dispute.fisherman, _dispute.deposit);

        emit DisputeCancelled(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit);
    }

    /**
     * @notice Make the subgraph service contract slash the indexer and reward the fisherman.
     * Give the fisherman a reward equal to the fishermanRewardPercentage of slashed amount
     * @param _indexer Address of the indexer
     * @param _tokensSlash Amount of tokens to slash from the indexer
     * @param _tokensStakeSnapshot Snapshot of the indexer's stake at the time of the dispute creation
     */
    function _slashIndexer(
        address _indexer,
        uint256 _tokensSlash,
        uint256 _tokensStakeSnapshot
    ) private returns (uint256) {
        ISubgraphService subgraphService_ = _getSubgraphService();

        // Get slashable amount for indexer
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(_indexer, address(subgraphService_));

        // Ensure slash amount is within the cap
        uint256 maxTokensSlash = _tokensStakeSnapshot.mulPPM(maxSlashingCut);
        require(
            _tokensSlash != 0 && _tokensSlash <= maxTokensSlash,
            DisputeManagerInvalidTokensSlash(_tokensSlash, maxTokensSlash)
        );

        // Rewards amount can only be extracted from service provider tokens so
        // we grab the minimum between the slash amount and indexer's tokens
        uint256 maxRewardableTokens = Math.min(_tokensSlash, provision.tokens);
        uint256 tokensRewards = uint256(fishermanRewardCut).mulPPM(maxRewardableTokens);

        subgraphService_.slash(_indexer, abi.encode(_tokensSlash, tokensRewards));
        return tokensRewards;
    }

    /**
     * @notice Internal: Set the arbitrator address.
     * @dev Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(_arbitrator != address(0), DisputeManagerInvalidZeroAddress());
        arbitrator = _arbitrator;
        emit ArbitratorSet(_arbitrator);
    }

    /**
     * @notice Internal: Set the dispute period.
     * @dev Update the dispute period to `_disputePeriod` in seconds
     * @param _disputePeriod Dispute period in seconds
     */
    function _setDisputePeriod(uint64 _disputePeriod) private {
        require(_disputePeriod != 0, DisputeManagerDisputePeriodZero());
        disputePeriod = _disputePeriod;
        emit DisputePeriodSet(_disputePeriod);
    }

    /**
     * @notice Internal: Set the dispute deposit required to create a dispute.
     * @dev Update the dispute deposit to `_disputeDeposit` Graph Tokens
     * @param _disputeDeposit The dispute deposit in Graph Tokens
     */
    function _setDisputeDeposit(uint256 _disputeDeposit) private {
        require(_disputeDeposit >= MIN_DISPUTE_DEPOSIT, DisputeManagerInvalidDisputeDeposit(_disputeDeposit));
        disputeDeposit = _disputeDeposit;
        emit DisputeDepositSet(_disputeDeposit);
    }

    /**
     * @notice Internal: Set the percent reward that the fisherman gets when slashing occurs.
     * @dev Update the reward percentage to `_percentage`
     * @param _fishermanRewardCut Reward as a percentage of indexer stake
     */
    function _setFishermanRewardCut(uint32 _fishermanRewardCut) private {
        require(
            _fishermanRewardCut <= MAX_FISHERMAN_REWARD_CUT,
            DisputeManagerInvalidFishermanReward(_fishermanRewardCut)
        );
        fishermanRewardCut = _fishermanRewardCut;
        emit FishermanRewardCutSet(_fishermanRewardCut);
    }

    /**
     * @notice Internal: Set the maximum percentage that can be used for slashing indexers.
     * @param _maxSlashingCut Max percentage slashing for disputes
     */
    function _setMaxSlashingCut(uint32 _maxSlashingCut) private {
        // Must be within 0% to 100% (inclusive)
        require(PPMMath.isValidPPM(_maxSlashingCut), DisputeManagerInvalidMaxSlashingCut(_maxSlashingCut));
        maxSlashingCut = _maxSlashingCut;
        emit MaxSlashingCutSet(maxSlashingCut);
    }

    /**
     * @notice Internal: Set the subgraph service address.
     * @dev Update the subgraph service to `_subgraphService`
     * @param _subgraphService The address of the subgraph service contract
     */
    function _setSubgraphService(address _subgraphService) private {
        require(_subgraphService != address(0), DisputeManagerInvalidZeroAddress());
        subgraphService = ISubgraphService(_subgraphService);
        emit SubgraphServiceSet(_subgraphService);
    }

    /**
     * @notice Get the address of the subgraph service
     * @dev Will revert if the subgraph service is not set
     * @return The subgraph service address
     */
    function _getSubgraphService() private view returns (ISubgraphService) {
        require(address(subgraphService) != address(0), DisputeManagerSubgraphServiceNotSet());
        return subgraphService;
    }

    /**
     * @notice Returns whether the dispute is for a conflicting attestation or not.
     * @param _dispute Dispute
     * @return True conflicting attestation dispute
     */
    function _isDisputeInConflict(Dispute storage _dispute) private view returns (bool) {
        return _dispute.relatedDisputeId != bytes32(0);
    }

    /**
     * @notice Get the total stake snapshot for and indexer.
     * @dev A few considerations:
     * - We include both indexer and delegators stake.
     * - Thawing stake is not excluded from the snapshot.
     * - Delegators stake is capped at the delegation ratio to prevent delegators from inflating the snapshot
     *   to increase the indexer slash amount.
     * @param _indexer Indexer address
     * @param _indexerStake Indexer's stake
     * @return Total stake snapshot
     */
    function _getStakeSnapshot(address _indexer, uint256 _indexerStake) private view returns (uint256) {
        ISubgraphService subgraphService_ = _getSubgraphService();
        uint256 delegatorsStake = _graphStaking().getDelegationPool(_indexer, address(subgraphService_)).tokens;
        uint256 delegatorsStakeMax = _indexerStake * uint256(subgraphService_.getDelegationRatio());
        uint256 stakeSnapshot = _indexerStake + MathUtils.min(delegatorsStake, delegatorsStakeMax);
        return stakeSnapshot;
    }
}
