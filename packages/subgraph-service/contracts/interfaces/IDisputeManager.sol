// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { Attestation } from "../libraries/Attestation.sol";

interface IDisputeManager {
    /// @notice Types of disputes that can be created
    enum DisputeType {
        Null,
        IndexingDispute,
        QueryDispute
    }

    /// @notice Status of a dispute
    enum DisputeStatus {
        Null,
        Accepted,
        Rejected,
        Drawn,
        Pending,
        Cancelled
    }

    /// @notice Disputes contain info necessary for the Arbitrator to verify and resolve
    struct Dispute {
        // Indexer that is being disputed
        address indexer;
        // Fisherman that created the dispute
        address fisherman;
        // Amount of tokens deposited by the fisherman
        uint256 deposit;
        // Link to a related dispute, used when creating dispute via conflicting attestations
        bytes32 relatedDisputeId;
        // Type of dispute
        DisputeType disputeType;
        // Status of the dispute
        DisputeStatus status;
        // Timestamp when the dispute was created
        uint256 createdAt;
        // Stake snapshot of the indexer at the time of the dispute (includes delegation up to the delegation ratio)
        uint256 stakeSnapshot;
    }

    /**
     * @notice Emitted when arbitrator is set.
     * @param arbitrator The address of the arbitrator.
     */
    event ArbitratorSet(address indexed arbitrator);

    /**
     * @notice Emitted when dispute period is set.
     * @param disputePeriod The dispute period in seconds.
     */
    event DisputePeriodSet(uint64 disputePeriod);

    /**
     * @notice Emitted when dispute deposit is set.
     * @param disputeDeposit The dispute deposit required to create a dispute.
     */
    event DisputeDepositSet(uint256 disputeDeposit);

    /**
     * @notice Emitted when max slashing cut is set.
     * @param maxSlashingCut The maximum slashing cut that can be set.
     */
    event MaxSlashingCutSet(uint32 maxSlashingCut);

    /**
     * @notice Emitted when fisherman reward cut is set.
     * @param fishermanRewardCut The fisherman reward cut.
     */
    event FishermanRewardCutSet(uint32 fishermanRewardCut);

    /**
     * @notice Emitted when subgraph service is set.
     * @param subgraphService The address of the subgraph service.
     */
    event SubgraphServiceSet(address indexed subgraphService);

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
        bytes attestation,
        uint256 stakeSnapshot
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
        address allocationId,
        bytes32 poi,
        uint256 stakeSnapshot
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

    /**
     * @dev Emitted when a dispute is cancelled by the fisherman.
     * The event emits the amount `tokens` returned to the fisherman.
     */
    event DisputeCancelled(bytes32 indexed disputeId, address indexed indexer, address indexed fisherman, uint256 tokens);

    // -- Errors --

    error DisputeManagerNotArbitrator();
    error DisputeManagerNotFisherman();
    error DisputeManagerInvalidZeroAddress();
    error DisputeManagerDisputePeriodZero();
    error DisputeManagerZeroTokens();
    error DisputeManagerInvalidDispute(bytes32 disputeId);
    error DisputeManagerInvalidDisputeDeposit(uint256 disputeDeposit);
    error DisputeManagerInvalidFishermanReward(uint32 cut);
    error DisputeManagerInvalidMaxSlashingCut(uint32 maxSlashingCut);
    error DisputeManagerInvalidTokensSlash(uint256 tokensSlash, uint256 maxTokensSlash);
    error DisputeManagerDisputeNotPending(IDisputeManager.DisputeStatus status);
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

    function setDisputePeriod(uint64 disputePeriod) external;

    function setArbitrator(address arbitrator) external;

    function setDisputeDeposit(uint256 disputeDeposit) external;

    function setFishermanRewardCut(uint32 cut) external;

    function setMaxSlashingCut(uint32 maxCut) external;

    // -- Dispute --

    function createQueryDispute(bytes calldata attestationData) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address allocationId, bytes32 poi) external returns (bytes32);

    function acceptDispute(bytes32 disputeId, uint256 tokensSlash) external;

    function rejectDispute(bytes32 disputeId) external;

    function drawDispute(bytes32 disputeId) external;

    function cancelDispute(bytes32 disputeId) external;

    function setSubgraphService(address subgraphService) external;

    // -- Getters --

    function getVerifierCut() external view returns (uint32);

    function getDisputePeriod() external view returns (uint64);

    function isDisputeCreated(bytes32 disputeId) external view returns (bool);

    function encodeReceipt(Attestation.Receipt memory receipt) external view returns (bytes32);

    function getAttestationIndexer(Attestation.State memory attestation) external view returns (address);

    function areConflictingAttestations(
        Attestation.State memory attestation1,
        Attestation.State memory attestation2
    ) external pure returns (bool);

    function getStakeSnapshot(address indexer) external view returns (uint256);
}
