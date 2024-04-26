// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;
pragma abicoder v2;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";
import { IDisputeManager } from "./interfaces/IDisputeManager.sol";
import { ISubgraphService } from "./interfaces/ISubgraphService.sol";
import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DisputeManagerV1Storage } from "./DisputeManagerStorage.sol";
import { Directory } from "./utilities/Directory.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TokenUtils } from "@graphprotocol/contracts/contracts/utils/TokenUtils.sol";
import { Allocation } from "./libraries/Allocation.sol";
import { PPMMath } from "./data-service/libraries/PPMMath.sol";
import { Attestation } from "./libraries/Attestation.sol";

/*
 * @title DisputeManager
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
contract DisputeManager is Ownable, DisputeManagerV1Storage, IDisputeManager {
    using PPMMath for uint256;

    // -- EIP-712  --

    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;

    // -- Errors --

    error DisputeManagerNotArbitrator();
    error DisputeManagerNotFisherman();
    error DisputeManagerArbitratorZeroAddress();
    error DisputeManagerSubgraphServiceZeroAddress();
    error DisputeManagerDisputePeriodZero();
    error DisputeManagerZeroTokens();
    error DisputeManagerInvalidDispute(bytes32 disputeId);
    error DisputeManagerInvalidMinimumDeposit(uint256 minimumDeposit);
    error DisputeManagerInvalidFishermanReward(uint32 percentage);
    error DisputeManagerInvalidMaxSlashingPercentage(uint32 maxSlashingPercentage);
    error DisputeManagerInvalidSlashAmount(uint256 slashAmount);
    error DisputeManagerInvalidDisputeStatus(IDisputeManager.DisputeStatus status);
    error DisputeManagerInsufficientDeposit(uint256 deposit, uint256 minimumDeposit);
    error DisputeManagerDisputeAlreadyCreated(bytes32 disputeId);
    error DisputeManagerDisputePeriodNotFinished();
    error DisputeManagerMustAcceptRelatedDispute(bytes32 disputeId, bytes32 relatedDisputeId);
    error DisputeManagerIndexerNotFound(address allocationId);
    error DisputeManagerNonMatchingSubgraphDeployment(bytes32 subgraphDeploymentId1, bytes32 subgraphDeploymentId2);
    error DisputeManagerNonConflictingAttestations(
        bytes32 requestCID1,
        bytes32 responseCID1,
        bytes32 subgraphDeploymentId1,
        bytes32 requestCID2,
        bytes32 responseCID2,
        bytes32 subgraphDeploymentId2
    );

    // -- Constants --

    // -- Immutable variables --

    IHorizonStaking public immutable staking;
    IGraphToken public immutable graphToken;

    // -- Mutable variables --

    ISubgraphService public subgraphService;

    // -- Events --

    /// Emitted when a contract parameter has been updated
    event ParameterUpdated(string param);

    /**
     * @dev Emitted when a query dispute is created for `subgraphDeploymentId` and `indexer`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman and `attestation` submitted.
     */
    event QueryDisputeCreated(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens,
        bytes32 subgraphDeploymentId,
        bytes attestation
    );

    /**
     * @dev Emitted when an indexing dispute is created for `allocationId` and `indexer`
     * by `fisherman`.
     * The event emits the amount of `tokens` deposited by the fisherman.
     */
    event IndexingDisputeCreated(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens,
        address allocationId
    );

    /**
     * @dev Emitted when arbitrator accepts a `disputeId` to `indexer` created by `fisherman`.
     * The event emits the amount `tokens` transferred to the fisherman, the deposit plus reward.
     */
    event DisputeAccepted(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator rejects a `disputeId` for `indexer` created by `fisherman`.
     * The event emits the amount `tokens` burned from the fisherman deposit.
     */
    event DisputeRejected(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    /**
     * @dev Emitted when arbitrator draw a `disputeId` for `indexer` created by `fisherman`.
     * The event emits the amount `tokens` used as deposit and returned to the fisherman.
     */
    event DisputeDrawn(bytes32 indexed disputeId, address indexed indexer, address indexed fisherman, uint256 tokens);

    /**
     * @dev Emitted when two disputes are in conflict to link them.
     * This event will be emitted after each DisputeCreated event is emitted
     * for each of the individual disputes.
     */
    event DisputeLinked(bytes32 indexed disputeId1, bytes32 indexed disputeId2);

    // -- Modifiers --

    function _onlyArbitrator() internal view {
        if (msg.sender != arbitrator) {
            revert DisputeManagerNotArbitrator();
        }
    }

    /**
     * @dev Check if the caller is the arbitrator.
     */
    modifier onlyArbitrator() {
        _onlyArbitrator();
        _;
    }

    modifier onlyPendingDispute(bytes32 _disputeId) {
        if (!isDisputeCreated(_disputeId)) {
            revert DisputeManagerInvalidDispute(_disputeId);
        }

        if (disputes[_disputeId].status != IDisputeManager.DisputeStatus.Pending) {
            revert DisputeManagerInvalidDisputeStatus(disputes[_disputeId].status);
        }
        _;
    }

    modifier onlyFisherman(bytes32 _disputeId) {
        if (!isDisputeCreated(_disputeId)) {
            revert DisputeManagerInvalidDispute(_disputeId);
        }

        if (msg.sender != disputes[_disputeId].fisherman) {
            revert DisputeManagerNotFisherman();
        }
        _;
    }

    // -- Functions --

    /**
     * @dev Initialize this contract.
     * @param _staking Address of staking contract
     * @param _graphToken Address of Graph token contract
     * @param _arbitrator Arbitrator role
     * @param _disputePeriod Dispute period in seconds
     * @param _minimumDeposit Minimum deposit required to create a Dispute
     * @param _fishermanRewardPercentage Percent of slashed funds for fisherman (ppm)
     * @param _maxSlashingPercentage Maximum percentage of indexer stake that can be slashed (ppm)
     */
    constructor(
        address _staking,
        address _graphToken,
        address _arbitrator,
        uint64 _disputePeriod,
        uint256 _minimumDeposit,
        uint32 _fishermanRewardPercentage,
        uint32 _maxSlashingPercentage
    ) Ownable(msg.sender) {
        staking = IHorizonStaking(_staking);
        graphToken = IGraphToken(_graphToken);

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
                block.chainid,
                address(this),
                DOMAIN_SALT
            )
        );
    }

    /**
     * @dev Create an indexing dispute for the arbitrator to resolve.
     * The disputes are created in reference to an allocationId
     * This function is called by a challenger that will need to `_deposit` at
     * least `minimumDeposit` GRT tokens.
     * @param _allocationId The allocation to dispute
     * @param _deposit Amount of tokens staked as deposit
     */
    function createIndexingDispute(address _allocationId, uint256 _deposit) external override returns (bytes32) {
        // Get funds from submitter
        _pullSubmitterDeposit(_deposit);

        // Create a dispute
        return _createIndexingDisputeWithAllocation(msg.sender, _deposit, _allocationId);
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
                Attestation.parse(_attestationData),
                _attestationData
            );
    }

    /**
     * @dev Create query disputes for two conflicting attestations.
     * A conflicting attestation is a proof presented by two different indexers
     * where for the same request on a subgraph the response is different.
     * For this type of dispute the submitter is not required to present a deposit
     * as one of the attestation is considered to be right.
     * Two linked disputes will be created and if the arbitrator resolve one, the other
     * one will be automatically resolved.
     * @param _attestationData1 First attestation data submitted
     * @param _attestationData2 Second attestation data submitted
     * @return DisputeId1, DisputeId2
     */
    function createQueryDisputeConflict(
        bytes calldata _attestationData1,
        bytes calldata _attestationData2
    ) external override returns (bytes32, bytes32) {
        address fisherman = msg.sender;

        // Parse each attestation
        Attestation.State memory attestation1 = Attestation.parse(_attestationData1);
        Attestation.State memory attestation2 = Attestation.parse(_attestationData2);

        // Test that attestations are conflicting
        if (!Attestation.areConflicting(attestation2, attestation1)) {
            revert DisputeManagerNonConflictingAttestations(
                attestation1.requestCID,
                attestation1.responseCID,
                attestation1.subgraphDeploymentId,
                attestation2.requestCID,
                attestation2.responseCID,
                attestation2.subgraphDeploymentId
            );
        }

        // Create the disputes
        // The deposit is zero for conflicting attestations
        bytes32 dId1 = _createQueryDisputeWithAttestation(fisherman, 0, attestation1, _attestationData1);
        bytes32 dId2 = _createQueryDisputeWithAttestation(fisherman, 0, attestation2, _attestationData2);

        // Store the linked disputes to be resolved
        disputes[dId1].relatedDisputeId = dId2;
        disputes[dId2].relatedDisputeId = dId1;

        // Emit event that links the two created disputes
        emit DisputeLinked(dId1, dId2);

        return (dId1, dId2);
    }

    /**
     * @dev The arbitrator accepts a dispute as being valid.
     * This function will revert if the indexer is not slashable, whether because it does not have
     * any stake available or the slashing percentage is configured to be zero. In those cases
     * a dispute must be resolved using drawDispute or rejectDispute.
     * @notice Accept a dispute with Id `_disputeId`
     * @param _disputeId Id of the dispute to be accepted
     * @param _slashAmount Amount of tokens to slash from the indexer
     */
    function acceptDispute(
        bytes32 _disputeId,
        uint256 _slashAmount
    ) external override onlyArbitrator onlyPendingDispute(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];

        // store the dispute status
        dispute.status = IDisputeManager.DisputeStatus.Accepted;

        // Slash
        uint256 tokensToReward = _slashIndexer(dispute.indexer, _slashAmount);

        // Give the fisherman their reward and their deposit back
        TokenUtils.pushTokens(graphToken, dispute.fisherman, tokensToReward + dispute.deposit);

        if (_isDisputeInConflict(dispute)) {
            rejectDispute(dispute.relatedDisputeId);
        }

        emit DisputeAccepted(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit + tokensToReward);
    }

    /**
     * @dev The arbitrator rejects a dispute as being invalid.
     * @notice Reject a dispute with Id `_disputeId`
     * @param _disputeId Id of the dispute to be rejected
     */
    function rejectDispute(bytes32 _disputeId) public override onlyArbitrator onlyPendingDispute(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];

        // store dispute status
        dispute.status = IDisputeManager.DisputeStatus.Rejected;

        // For conflicting disputes, the related dispute must be accepted
        if (_isDisputeInConflict(dispute)) {
            revert DisputeManagerMustAcceptRelatedDispute(_disputeId, dispute.relatedDisputeId);
        }

        // Burn the fisherman's deposit
        TokenUtils.burnTokens(graphToken, dispute.deposit);

        emit DisputeRejected(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit);
    }

    /**
     * @dev The arbitrator draws dispute.
     * @notice Ignore a dispute with Id `_disputeId`
     * @param _disputeId Id of the dispute to be disregarded
     */
    function drawDispute(bytes32 _disputeId) external override onlyArbitrator onlyPendingDispute(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];

        // Return deposit to the fisherman
        TokenUtils.pushTokens(graphToken, dispute.fisherman, dispute.deposit);

        // resolve related dispute if any
        _drawDisputeInConflict(dispute);

        // store dispute status
        dispute.status = IDisputeManager.DisputeStatus.Drawn;

        emit DisputeDrawn(_disputeId, dispute.indexer, dispute.fisherman, dispute.deposit);
    }

    /**
     * @dev Once the dispute period ends, if the disput status remains Pending,
     * the fisherman can cancel the dispute and get back their initial deposit.
     * @notice Cancel a dispute with Id `_disputeId`
     * @param _disputeId Id of the dispute to be cancelled
     */
    function cancelDispute(
        bytes32 _disputeId
    ) external override onlyFisherman(_disputeId) onlyPendingDispute(_disputeId) {
        Dispute storage dispute = disputes[_disputeId];

        // Check if dispute period has finished
        if (block.timestamp <= dispute.createdAt + disputePeriod) {
            revert DisputeManagerDisputePeriodNotFinished();
        }

        // Return deposit to the fisherman
        TokenUtils.pushTokens(graphToken, dispute.fisherman, dispute.deposit);

        // resolve related dispute if any
        _cancelDisputeInConflict(dispute);

        // store dispute status
        dispute.status = IDisputeManager.DisputeStatus.Cancelled;
    }

    /**
     * @dev Set the subgraph service address.
     * @notice Update the subgraph service to `_subgraphService`
     * @param _subgraphService The address of the subgraph service contract
     */
    function setSubgraphService(address _subgraphService) external onlyOwner {
        _setSubgraphService(_subgraphService);
    }

    /**
     * @dev Set the arbitrator address.
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address _arbitrator) external override onlyOwner {
        _setArbitrator(_arbitrator);
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
     * @dev Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function setMinimumDeposit(uint256 _minimumDeposit) external override onlyOwner {
        _setMinimumDeposit(_minimumDeposit);
    }

    /**
     * @dev Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of indexer stake
     */
    function setFishermanRewardPercentage(uint32 _percentage) external override onlyOwner {
        _setFishermanRewardPercentage(_percentage);
    }

    /**
     * @dev Set the maximum percentage that can be used for slashing indexers.
     * @param _maxSlashingPercentage Max percentage slashing for disputes
     */
    function setMaxSlashingPercentage(uint32 _maxSlashingPercentage) external override onlyOwner {
        _setMaxSlashingPercentage(_maxSlashingPercentage);
    }

    function areConflictingAttestations(
        Attestation.State memory _attestation1,
        Attestation.State memory _attestation2
    ) external pure override returns (bool) {
        return Attestation.areConflicting(_attestation1, _attestation2);
    }

    /**
     * @dev Get the verifier cut.
     * @return Verifier cut in percentage (ppm)
     */
    function getVerifierCut() external view returns (uint32) {
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
     * @notice Return if dispute with Id `_disputeId` exists
     * @param _disputeId True if dispute already exists
     */
    function isDisputeCreated(bytes32 _disputeId) public view override returns (bool) {
        return disputes[_disputeId].status != DisputeStatus.Null;
    }

    /**
     * @dev Get the message hash that a indexer used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @notice Return the message hash used to sign the receipt
     * @param _receipt Receipt returned by indexer and submitted by fisherman
     * @return Message hash used to sign the receipt
     */
    function encodeReceipt(Attestation.Receipt memory _receipt) public view override returns (bytes32) {
        return Attestation.encodeReceipt(_receipt, DOMAIN_SEPARATOR);
    }

    /**
     * @dev Returns the indexer that signed an attestation.
     * @param _attestation Attestation
     * @return indexer address
     */
    function getAttestationIndexer(Attestation.State memory _attestation) public view override returns (address) {
        // Get attestation signer. Indexers signs with the allocationId
        address allocationId = Attestation.recoverSigner(_attestation, DOMAIN_SEPARATOR);

        Allocation.State memory alloc = subgraphService.getAllocation(allocationId);
        if (alloc.indexer == address(0)) {
            revert DisputeManagerIndexerNotFound(allocationId);
        }
        if (alloc.subgraphDeploymentId != _attestation.subgraphDeploymentId) {
            revert DisputeManagerNonMatchingSubgraphDeployment(
                alloc.subgraphDeploymentId,
                _attestation.subgraphDeploymentId
            );
        }
        return alloc.indexer;
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
        IHorizonStaking.Provision memory provision = staking.getProvision(indexer, address(subgraphService));
        if (provision.tokens == 0) {
            revert DisputeManagerZeroTokens();
        }

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
        if (isDisputeCreated(disputeId)) {
            revert DisputeManagerDisputeAlreadyCreated(disputeId);
        }

        // Store dispute
        disputes[disputeId] = Dispute(
            indexer,
            _fisherman,
            _deposit,
            0, // no related dispute,
            DisputeType.QueryDispute,
            IDisputeManager.DisputeStatus.Pending,
            block.timestamp
        );

        emit QueryDisputeCreated(
            disputeId,
            indexer,
            _fisherman,
            _deposit,
            _attestation.subgraphDeploymentId,
            _attestationData
        );

        return disputeId;
    }

    /**
     * @dev Create indexing dispute internal function.
     * @param _fisherman The challenger creating the dispute
     * @param _deposit Amount of tokens staked as deposit
     * @param _allocationId Allocation disputed
     */
    function _createIndexingDisputeWithAllocation(
        address _fisherman,
        uint256 _deposit,
        address _allocationId
    ) private returns (bytes32) {
        // Create a disputeId
        bytes32 disputeId = keccak256(abi.encodePacked(_allocationId));

        // Only one dispute for an allocationId at a time
        if (isDisputeCreated(disputeId)) {
            revert DisputeManagerDisputeAlreadyCreated(disputeId);
        }

        // Allocation must exist
        // TODO: Check ISubgraphService for Allocation
        // TODO: Check ISubgraphService for getAllocation(...)
        Allocation.State memory alloc = subgraphService.getAllocation(_allocationId);
        address indexer = alloc.indexer;
        if (indexer == address(0)) {
            revert DisputeManagerIndexerNotFound(_allocationId);
        }

        // The indexer must be disputable
        IHorizonStaking.Provision memory provision = staking.getProvision(indexer, address(subgraphService));
        if (provision.tokens == 0) {
            revert DisputeManagerZeroTokens();
        }

        // Store dispute
        disputes[disputeId] = Dispute(
            alloc.indexer,
            _fisherman,
            _deposit,
            0,
            DisputeType.IndexingDispute,
            IDisputeManager.DisputeStatus.Pending,
            block.timestamp
        );

        emit IndexingDisputeCreated(disputeId, alloc.indexer, _fisherman, _deposit, _allocationId);

        return disputeId;
    }

    /**
     * @dev Resolve the conflicting dispute if there is any for the one passed to this function.
     * @param _dispute Dispute
     * @return True if resolved
     */
    function _drawDisputeInConflict(Dispute memory _dispute) private returns (bool) {
        if (_isDisputeInConflict(_dispute)) {
            bytes32 relatedDisputeId = _dispute.relatedDisputeId;
            Dispute storage relatedDispute = disputes[relatedDisputeId];
            relatedDispute.status = IDisputeManager.DisputeStatus.Drawn;
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
            bytes32 relatedDisputeId = _dispute.relatedDisputeId;
            Dispute storage relatedDispute = disputes[relatedDisputeId];
            relatedDispute.status = IDisputeManager.DisputeStatus.Cancelled;
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
        if (_deposit < minimumDeposit) {
            revert DisputeManagerInsufficientDeposit(_deposit, minimumDeposit);
        }

        // Transfer tokens to deposit from fisherman to this contract
        TokenUtils.pullTokens(graphToken, msg.sender, _deposit);
    }

    /**
     * @dev Make the subgraph service contract slash the indexer and reward the challenger.
     * Give the challenger a reward equal to the fishermanRewardPercentage of slashed amount
     * @param _indexer Address of the indexer
     * @param _slashAmount Amount of tokens to slash from the indexer
     */
    function _slashIndexer(address _indexer, uint256 _slashAmount) private returns (uint256 rewardsAmount) {
        // Get slashable amount for indexer
        IHorizonStaking.Provision memory provision = staking.getProvision(_indexer, address(subgraphService));
        uint256 totalProvisionTokens = provision.tokens + provision.delegatedTokens; // slashable tokens

        // Get slash amount
        uint256 maxSlashAmount = uint256(maxSlashingPercentage).mulPPM(totalProvisionTokens);
        if (_slashAmount == 0) {
            revert DisputeManagerInvalidSlashAmount(_slashAmount);
        }

        if (_slashAmount > maxSlashAmount) {
            revert DisputeManagerInvalidSlashAmount(_slashAmount);
        }

        // Rewards amount can only be extracted from service poriver tokens so
        // we grab the minimum between the slash amount and indexer's tokens
        uint256 maxRewardableTokens = Math.min(_slashAmount, provision.tokens);
        rewardsAmount = uint256(fishermanRewardPercentage).mulPPM(maxRewardableTokens);

        subgraphService.slash(_indexer, abi.encode(_slashAmount, rewardsAmount));
        return rewardsAmount;
    }

    /**
     * @dev Internal: Set the subgraph service address.
     * @notice Update the subgraph service to `_subgraphService`
     * @param _subgraphService The address of the subgraph service contract
     */
    function _setSubgraphService(address _subgraphService) private {
        if (_subgraphService == address(0)) {
            revert DisputeManagerSubgraphServiceZeroAddress();
        }
        subgraphService = ISubgraphService(_subgraphService);
        emit ParameterUpdated("subgraphService");
    }

    /**
     * @dev Internal: Set the arbitrator address.
     * @notice Update the arbitrator to `_arbitrator`
     * @param _arbitrator The address of the arbitration contract or party
     */
    function _setArbitrator(address _arbitrator) private {
        if (_arbitrator == address(0)) {
            revert DisputeManagerArbitratorZeroAddress();
        }
        arbitrator = _arbitrator;
        emit ParameterUpdated("arbitrator");
    }

    /**
     * @dev Internal: Set the dispute period.
     * @notice Update the dispute period to `_disputePeriod` in seconds
     * @param _disputePeriod Dispute period in seconds
     */
    function _setDisputePeriod(uint64 _disputePeriod) private {
        if (_disputePeriod == 0) {
            revert DisputeManagerDisputePeriodZero();
        }
        disputePeriod = _disputePeriod;
        emit ParameterUpdated("disputePeriod");
    }

    /**
     * @dev Internal: Set the minimum deposit required to create a dispute.
     * @notice Update the minimum deposit to `_minimumDeposit` Graph Tokens
     * @param _minimumDeposit The minimum deposit in Graph Tokens
     */
    function _setMinimumDeposit(uint256 _minimumDeposit) private {
        if (_minimumDeposit == 0) {
            revert DisputeManagerInvalidMinimumDeposit(_minimumDeposit);
        }
        minimumDeposit = _minimumDeposit;
        emit ParameterUpdated("minimumDeposit");
    }

    /**
     * @dev Internal: Set the percent reward that the fisherman gets when slashing occurs.
     * @notice Update the reward percentage to `_percentage`
     * @param _percentage Reward as a percentage of indexer stake
     */
    function _setFishermanRewardPercentage(uint32 _percentage) private {
        // Must be within 0% to 100% (inclusive)
        if (!PPMMath.isValidPPM(_percentage)) {
            revert DisputeManagerInvalidFishermanReward(_percentage);
        }
        fishermanRewardPercentage = _percentage;
        emit ParameterUpdated("fishermanRewardPercentage");
    }

    /**
     * @dev Internal: Set the maximum percentage that can be used for slashing indexers.
     * @param _maxSlashingPercentage Max percentage slashing for disputes
     */
    function _setMaxSlashingPercentage(uint32 _maxSlashingPercentage) private {
        // Must be within 0% to 100% (inclusive)
        if (!PPMMath.isValidPPM(_maxSlashingPercentage)) {
            revert DisputeManagerInvalidMaxSlashingPercentage(_maxSlashingPercentage);
        }
        maxSlashingPercentage = _maxSlashingPercentage;
        emit ParameterUpdated("maxSlashingPercentage");
    }

    /**
     * @dev Returns whether the dispute is for a conflicting attestation or not.
     * @param _dispute Dispute
     * @return True conflicting attestation dispute
     */
    function _isDisputeInConflict(Dispute memory _dispute) private view returns (bool) {
        bytes32 relatedId = _dispute.relatedDisputeId;
        // this is so the check returns false when rejecting the related dispute.
        return relatedId != 0 && disputes[relatedId].status == IDisputeManager.DisputeStatus.Pending;
    }
}
