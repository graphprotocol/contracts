// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.26;

import { Attestation } from "../libraries/Attestation.sol";

interface IDisputeManager {
    // -- Dispute --

    enum DisputeType {
        Null,
        IndexingDispute,
        QueryDispute
    }

    enum DisputeStatus {
        Null,
        Accepted,
        Rejected,
        Drawn,
        Pending,
        Cancelled
    }

    // Disputes contain info necessary for the Arbitrator to verify and resolve
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeId;
        DisputeType disputeType;
        DisputeStatus status;
        uint256 createdAt;
    }

    // -- Events --
    event ArbitratorSet(address arbitrator);
    event DisputePeriodSet(uint64 disputePeriod);
    event MinimumDepositSet(uint256 minimumDeposit);
    event MaxSlashingCutSet(uint32 maxSlashingCut);
    event FishermanRewardCutSet(uint32 fishermanRewardCut);
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

    // -- Errors --

    error DisputeManagerNotArbitrator();
    error DisputeManagerNotFisherman();
    error DisputeManagerInvalidZeroAddress();
    error DisputeManagerDisputePeriodZero();
    error DisputeManagerZeroTokens();
    error DisputeManagerInvalidDispute(bytes32 disputeId);
    error DisputeManagerInvalidMinimumDeposit(uint256 minimumDeposit);
    error DisputeManagerInvalidFishermanReward(uint32 cut);
    error DisputeManagerInvalidMaxSlashingCut(uint32 maxSlashingCut);
    error DisputeManagerInvalidTokensSlash(uint256 tokensSlash);
    error DisputeManagerDisputeNotPending(IDisputeManager.DisputeStatus status);
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

    // -- Attestation --

    // -- Configuration --

    function setDisputePeriod(uint64 disputePeriod) external;

    function setArbitrator(address arbitrator) external;

    function setMinimumDeposit(uint256 minimumDeposit) external;

    function setFishermanRewardCut(uint32 cut) external;

    function setMaxSlashingCut(uint32 maxCut) external;

    // -- Dispute --

    function createQueryDispute(bytes calldata attestationData, uint256 deposit) external returns (bytes32);

    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

    function createIndexingDispute(address allocationId, uint256 deposit) external returns (bytes32);

    function acceptDispute(bytes32 disputeId, uint256 tokensSlash) external;

    function rejectDispute(bytes32 disputeId) external;

    function drawDispute(bytes32 disputeId) external;

    function cancelDispute(bytes32 disputeId) external;

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
}
