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

    /// @notice Maximum value for fisherman reward cut in PPM
    uint32 public constant MAX_FISHERMAN_REWARD_CUT = 500000; // 50%

    /// @notice Minimum value for dispute deposit
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

    /// @inheritdoc IDisputeManager
    function initialize(
        address owner,
        address arbitrator,
        uint64 disputePeriod,
        uint256 disputeDeposit,
        uint32 fishermanRewardCut_,
        uint32 maxSlashingCut_
    ) external override initializer {
        __Ownable_init(owner);
        __AttestationManager_init();

        _setArbitrator(arbitrator);
        _setDisputePeriod(disputePeriod);
        _setDisputeDeposit(disputeDeposit);
        _setFishermanRewardCut(fishermanRewardCut_);
        _setMaxSlashingCut(maxSlashingCut_);
    }

    /// @inheritdoc IDisputeManager
    function createIndexingDispute(address allocationId, bytes32 poi) external override returns (bytes32) {
        // Get funds from fisherman
        _graphToken().pullTokens(msg.sender, disputeDeposit);

        // Create a dispute
        return _createIndexingDisputeWithAllocation(msg.sender, disputeDeposit, allocationId, poi);
    }

    /// @inheritdoc IDisputeManager
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

    /// @inheritdoc IDisputeManager
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

    /// @inheritdoc IDisputeManager
    function createAndAcceptLegacyDispute(
        address allocationId,
        address fisherman,
        uint256 tokensSlash,
        uint256 tokensRewards
    ) external override onlyArbitrator returns (bytes32) {
        // Create a disputeId
        bytes32 disputeId = keccak256(abi.encodePacked(allocationId, "legacy"));

        // Get the indexer for the legacy allocation
        address indexer = _graphStaking().getAllocation(allocationId).indexer;
        require(indexer != address(0), DisputeManagerIndexerNotFound(allocationId));

        // Store dispute
        disputes[disputeId] = Dispute(
            indexer,
            fisherman,
            0,
            0,
            DisputeType.LegacyDispute,
            IDisputeManager.DisputeStatus.Accepted,
            block.timestamp,
            block.timestamp + disputePeriod,
            0
        );

        // Slash the indexer
        ISubgraphService subgraphService_ = _getSubgraphService();
        subgraphService_.slash(indexer, abi.encode(tokensSlash, tokensRewards));

        // Reward the fisherman
        _graphToken().pushTokens(fisherman, tokensRewards);

        emit LegacyDisputeCreated(disputeId, indexer, fisherman, allocationId, tokensSlash, tokensRewards);
        emit DisputeAccepted(disputeId, indexer, fisherman, tokensRewards);

        return disputeId;
    }

    /// @inheritdoc IDisputeManager
    function acceptDispute(
        bytes32 disputeId,
        uint256 tokensSlash
    ) external override onlyArbitrator onlyPendingDispute(disputeId) {
        require(!_isDisputeInConflict(disputes[disputeId]), DisputeManagerDisputeInConflict(disputeId));
        Dispute storage dispute = disputes[disputeId];
        _acceptDispute(disputeId, dispute, tokensSlash);
    }

    /// @inheritdoc IDisputeManager
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

    /// @inheritdoc IDisputeManager
    function rejectDispute(bytes32 disputeId) external override onlyArbitrator onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        require(!_isDisputeInConflict(dispute), DisputeManagerDisputeInConflict(disputeId));
        _rejectDispute(disputeId, dispute);
    }

    /// @inheritdoc IDisputeManager
    function drawDispute(bytes32 disputeId) external override onlyArbitrator onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];
        _drawDispute(disputeId, dispute);

        if (_isDisputeInConflict(dispute)) {
            _drawDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId]);
        }
    }

    /// @inheritdoc IDisputeManager
    function cancelDispute(bytes32 disputeId) external override onlyFisherman(disputeId) onlyPendingDispute(disputeId) {
        Dispute storage dispute = disputes[disputeId];

        // Check if dispute period has finished
        require(dispute.cancellableAt <= block.timestamp, DisputeManagerDisputePeriodNotFinished());
        _cancelDispute(disputeId, dispute);

        if (_isDisputeInConflict(dispute)) {
            _cancelDispute(dispute.relatedDisputeId, disputes[dispute.relatedDisputeId]);
        }
    }

    /// @inheritdoc IDisputeManager
    function setArbitrator(address arbitrator) external override onlyOwner {
        _setArbitrator(arbitrator);
    }

    /// @inheritdoc IDisputeManager
    function setDisputePeriod(uint64 disputePeriod) external override onlyOwner {
        _setDisputePeriod(disputePeriod);
    }

    /// @inheritdoc IDisputeManager
    function setDisputeDeposit(uint256 disputeDeposit) external override onlyOwner {
        _setDisputeDeposit(disputeDeposit);
    }

    /// @inheritdoc IDisputeManager
    function setFishermanRewardCut(uint32 fishermanRewardCut_) external override onlyOwner {
        _setFishermanRewardCut(fishermanRewardCut_);
    }

    /// @inheritdoc IDisputeManager
    function setMaxSlashingCut(uint32 maxSlashingCut_) external override onlyOwner {
        _setMaxSlashingCut(maxSlashingCut_);
    }

    /// @inheritdoc IDisputeManager
    function setSubgraphService(address subgraphService) external override onlyOwner {
        _setSubgraphService(subgraphService);
    }

    /// @inheritdoc IDisputeManager
    function encodeReceipt(Attestation.Receipt calldata receipt) external view override returns (bytes32) {
        return _encodeReceipt(receipt);
    }

    /// @inheritdoc IDisputeManager
    function getFishermanRewardCut() external view override returns (uint32) {
        return fishermanRewardCut;
    }

    /// @inheritdoc IDisputeManager
    function getDisputePeriod() external view override returns (uint64) {
        return disputePeriod;
    }

    /// @inheritdoc IDisputeManager
    function getStakeSnapshot(address indexer) external view override returns (uint256) {
        IHorizonStaking.Provision memory provision = _graphStaking().getProvision(
            indexer,
            address(_getSubgraphService())
        );
        return _getStakeSnapshot(indexer, provision.tokens);
    }

    /// @inheritdoc IDisputeManager
    function areConflictingAttestations(
        Attestation.State calldata attestation1,
        Attestation.State calldata attestation2
    ) external pure override returns (bool) {
        return Attestation.areConflicting(attestation1, attestation2);
    }

    /// @inheritdoc IDisputeManager
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

    /// @inheritdoc IDisputeManager
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
        uint256 cancellableAt = block.timestamp + disputePeriod;
        disputes[disputeId] = Dispute(
            indexer,
            _fisherman,
            _deposit,
            0, // no related dispute,
            DisputeType.QueryDispute,
            IDisputeManager.DisputeStatus.Pending,
            block.timestamp,
            cancellableAt,
            stakeSnapshot
        );

        emit QueryDisputeCreated(
            disputeId,
            indexer,
            _fisherman,
            _deposit,
            _attestation.subgraphDeploymentId,
            _attestationData,
            cancellableAt,
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
     * @return The dispute id
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
            block.timestamp + disputePeriod,
            stakeSnapshot
        );

        emit IndexingDisputeCreated(disputeId, alloc.indexer, _fisherman, _deposit, _allocationId, _poi, stakeSnapshot);

        return disputeId;
    }

    /**
     * @notice Accept a dispute
     * @param _disputeId The id of the dispute
     * @param _dispute The dispute
     * @param _tokensSlashed The amount of tokens to slash
     */
    function _acceptDispute(bytes32 _disputeId, Dispute storage _dispute, uint256 _tokensSlashed) private {
        uint256 tokensToReward = _slashIndexer(_dispute.indexer, _tokensSlashed, _dispute.stakeSnapshot);
        _dispute.status = IDisputeManager.DisputeStatus.Accepted;
        _graphToken().pushTokens(_dispute.fisherman, tokensToReward + _dispute.deposit);

        emit DisputeAccepted(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit + tokensToReward);
    }

    /**
     * @notice Reject a dispute
     * @param _disputeId The id of the dispute
     * @param _dispute The dispute
     */
    function _rejectDispute(bytes32 _disputeId, Dispute storage _dispute) private {
        _dispute.status = IDisputeManager.DisputeStatus.Rejected;
        _graphToken().burnTokens(_dispute.deposit);

        emit DisputeRejected(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit);
    }

    /**
     * @notice Draw a dispute
     * @param _disputeId The id of the dispute
     * @param _dispute The dispute
     */
    function _drawDispute(bytes32 _disputeId, Dispute storage _dispute) private {
        _dispute.status = IDisputeManager.DisputeStatus.Drawn;
        _graphToken().pushTokens(_dispute.fisherman, _dispute.deposit);

        emit DisputeDrawn(_disputeId, _dispute.indexer, _dispute.fisherman, _dispute.deposit);
    }

    /**
     * @notice Cancel a dispute
     * @param _disputeId The id of the dispute
     * @param _dispute The dispute
     */
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
     * @return The amount of tokens rewarded to the fisherman
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
     * @notice Set the arbitrator address.
     * @dev Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        require(_arbitrator != address(0), DisputeManagerInvalidZeroAddress());
        arbitrator = _arbitrator;
        emit ArbitratorSet(_arbitrator);
    }

    /**
     * @notice Set the dispute period.
     * @dev Update the dispute period to `_disputePeriod` in seconds
     * @param _disputePeriod Dispute period in seconds
     */
    function _setDisputePeriod(uint64 _disputePeriod) private {
        require(_disputePeriod != 0, DisputeManagerDisputePeriodZero());
        disputePeriod = _disputePeriod;
        emit DisputePeriodSet(_disputePeriod);
    }

    /**
     * @notice Set the dispute deposit required to create a dispute.
     * @dev Update the dispute deposit to `_disputeDeposit` Graph Tokens
     * @param _disputeDeposit The dispute deposit in Graph Tokens
     */
    function _setDisputeDeposit(uint256 _disputeDeposit) private {
        require(_disputeDeposit >= MIN_DISPUTE_DEPOSIT, DisputeManagerInvalidDisputeDeposit(_disputeDeposit));
        disputeDeposit = _disputeDeposit;
        emit DisputeDepositSet(_disputeDeposit);
    }

    /**
     * @notice Set the percent reward that the fisherman gets when slashing occurs.
     * @dev Update the reward percentage to `_percentage`
     * @param _fishermanRewardCut The fisherman reward cut, in PPM
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
     * @notice Set the maximum percentage that can be used for slashing indexers.
     * @param _maxSlashingCut Max percentage slashing for disputes, in PPM
     */
    function _setMaxSlashingCut(uint32 _maxSlashingCut) private {
        require(PPMMath.isValidPPM(_maxSlashingCut), DisputeManagerInvalidMaxSlashingCut(_maxSlashingCut));
        maxSlashingCut = _maxSlashingCut;
        emit MaxSlashingCutSet(maxSlashingCut);
    }

    /**
     * @notice Set the subgraph service address.
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
     * - Delegator's stake is not considered if delegation slashing is disabled.
     * @param _indexer Indexer address
     * @param _indexerStake Indexer's stake
     * @return Total stake snapshot
     */
    function _getStakeSnapshot(address _indexer, uint256 _indexerStake) private view returns (uint256) {
        ISubgraphService subgraphService_ = _getSubgraphService();
        IHorizonStaking staking = _graphStaking();

        if (staking.isDelegationSlashingEnabled()) {
            uint256 delegatorsStake = staking.getDelegationPool(_indexer, address(subgraphService_)).tokens;
            uint256 delegatorsStakeMax = _indexerStake * uint256(subgraphService_.getDelegationRatio());
            return _indexerStake + MathUtils.min(delegatorsStake, delegatorsStakeMax);
        } else {
            return _indexerStake;
        }
    }
}
