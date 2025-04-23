// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { Attestation } from "../libraries/Attestation.sol";

/**
 * @title IDisputeManager
 * @notice Interface for the {Dispute Manager} contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IDisputeManager {
    /// @notice Types of disputes that can be created
    enum DisputeType {
        Null,
        IndexingDispute,
        QueryDispute,
        LegacyDispute
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

    /**
     * @notice Dispute details
     * @param indexer The indexer that is being disputed
     * @param fisherman The fisherman that created the dispute
     * @param deposit The amount of tokens deposited by the fisherman
     * @param relatedDisputeId The link to a related dispute, used when creating dispute via conflicting attestations
     * @param disputeType The type of dispute
     * @param status The status of the dispute
     * @param createdAt The timestamp when the dispute was created
     * @param stakeSnapshot The stake snapshot of the indexer at the time of the dispute (includes delegation up to the delegation ratio)
     */
    struct Dispute {
        address indexer;
        address fisherman;
        uint256 deposit;
        bytes32 relatedDisputeId;
        DisputeType disputeType;
        DisputeStatus status;
        uint256 createdAt;
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
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens deposited by the fisherman
     * @param subgraphDeploymentId The subgraph deployment id
     * @param attestation The attestation
     * @param stakeSnapshot The stake snapshot of the indexer at the time of the dispute
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
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens deposited by the fisherman
     * @param allocationId The allocation id
     * @param poi The POI
     * @param stakeSnapshot The stake snapshot of the indexer at the time of the dispute
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
     * @dev Emitted when a legacy dispute is created for `allocationId` and `fisherman`.
     * The event emits the amount of `tokensSlash` to slash and `tokensRewards` to reward the fisherman.
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address to be credited with the rewards
     * @param allocationId The allocation id
     * @param tokensSlash The amount of tokens to slash
     * @param tokensRewards The amount of tokens to reward the fisherman
     */
    event LegacyDisputeCreated(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        address allocationId,
        uint256 tokensSlash,
        uint256 tokensRewards
    );

    /**
     * @dev Emitted when arbitrator accepts a `disputeId` to `indexer` created by `fisherman`.
     * The event emits the amount `tokens` transferred to the fisherman, the deposit plus reward.
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens transferred to the fisherman, the deposit plus reward
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
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens burned from the fisherman deposit
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
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens returned to the fisherman - the deposit
     */
    event DisputeDrawn(bytes32 indexed disputeId, address indexed indexer, address indexed fisherman, uint256 tokens);

    /**
     * @dev Emitted when two disputes are in conflict to link them.
     * This event will be emitted after each DisputeCreated event is emitted
     * for each of the individual disputes.
     * @param disputeId1 The first dispute id
     * @param disputeId2 The second dispute id
     */
    event DisputeLinked(bytes32 indexed disputeId1, bytes32 indexed disputeId2);

    /**
     * @dev Emitted when a dispute is cancelled by the fisherman.
     * The event emits the amount `tokens` returned to the fisherman.
     * @param disputeId The dispute id
     * @param indexer The indexer address
     * @param fisherman The fisherman address
     * @param tokens The amount of tokens returned to the fisherman - the deposit
     */
    event DisputeCancelled(
        bytes32 indexed disputeId,
        address indexed indexer,
        address indexed fisherman,
        uint256 tokens
    );

    // -- Errors --

    /**
     * @notice Thrown when the caller is not the arbitrator
     */
    error DisputeManagerNotArbitrator();

    /**
     * @notice Thrown when the caller is not the fisherman
     */
    error DisputeManagerNotFisherman();

    /**
     * @notice Thrown when the address is the zero address
     */
    error DisputeManagerInvalidZeroAddress();

    /**
     * @notice Thrown when the dispute period is zero
     */
    error DisputeManagerDisputePeriodZero();

    /**
     * @notice Thrown when the indexer being disputed has no provisioned tokens
     */
    error DisputeManagerZeroTokens();

    /**
     * @notice Thrown when the dispute id is invalid
     * @param disputeId The dispute id
     */
    error DisputeManagerInvalidDispute(bytes32 disputeId);

    /**
     * @notice Thrown when the dispute deposit is invalid - less than the minimum dispute deposit
     * @param disputeDeposit The dispute deposit
     */
    error DisputeManagerInvalidDisputeDeposit(uint256 disputeDeposit);

    /**
     * @notice Thrown when the fisherman reward cut is invalid
     * @param cut The fisherman reward cut
     */
    error DisputeManagerInvalidFishermanReward(uint32 cut);

    /**
     * @notice Thrown when the max slashing cut is invalid
     * @param maxSlashingCut The max slashing cut
     */
    error DisputeManagerInvalidMaxSlashingCut(uint32 maxSlashingCut);

    /**
     * @notice Thrown when the tokens slash is invalid
     * @param tokensSlash The tokens slash
     * @param maxTokensSlash The max tokens slash
     */
    error DisputeManagerInvalidTokensSlash(uint256 tokensSlash, uint256 maxTokensSlash);

    /**
     * @notice Thrown when the dispute is not pending
     * @param status The status of the dispute
     */
    error DisputeManagerDisputeNotPending(IDisputeManager.DisputeStatus status);

    /**
     * @notice Thrown when the dispute is already created
     * @param disputeId The dispute id
     */
    error DisputeManagerDisputeAlreadyCreated(bytes32 disputeId);

    /**
     * @notice Thrown when the dispute period is not finished
     */
    error DisputeManagerDisputePeriodNotFinished();

    /**
     * @notice Thrown when the dispute is in conflict
     * @param disputeId The dispute id
     */
    error DisputeManagerDisputeInConflict(bytes32 disputeId);

    /**
     * @notice Thrown when the dispute is not in conflict
     * @param disputeId The dispute id
     */
    error DisputeManagerDisputeNotInConflict(bytes32 disputeId);

    /**
     * @notice Thrown when the dispute must be accepted
     * @param disputeId The dispute id
     * @param relatedDisputeId The related dispute id
     */
    error DisputeManagerMustAcceptRelatedDispute(bytes32 disputeId, bytes32 relatedDisputeId);

    /**
     * @notice Thrown when the indexer is not found
     * @param allocationId The allocation id
     */
    error DisputeManagerIndexerNotFound(address allocationId);

    /**
     * @notice Thrown when the subgraph deployment is not matching
     * @param subgraphDeploymentId1 The subgraph deployment id of the first attestation
     * @param subgraphDeploymentId2 The subgraph deployment id of the second attestation
     */
    error DisputeManagerNonMatchingSubgraphDeployment(bytes32 subgraphDeploymentId1, bytes32 subgraphDeploymentId2);

    /**
     * @notice Thrown when the attestations are not conflicting
     * @param requestCID1 The request CID of the first attestation
     * @param responseCID1 The response CID of the first attestation
     * @param subgraphDeploymentId1 The subgraph deployment id of the first attestation
     * @param requestCID2 The request CID of the second attestation
     * @param responseCID2 The response CID of the second attestation
     * @param subgraphDeploymentId2 The subgraph deployment id of the second attestation
     */
    error DisputeManagerNonConflictingAttestations(
        bytes32 requestCID1,
        bytes32 responseCID1,
        bytes32 subgraphDeploymentId1,
        bytes32 requestCID2,
        bytes32 responseCID2,
        bytes32 subgraphDeploymentId2
    );

    /**
     * @notice Thrown when attempting to get the subgraph service before it is set
     */
    error DisputeManagerSubgraphServiceNotSet();

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
    ) external;

    /**
     * @notice Set the dispute period.
     * @dev Update the dispute period to `_disputePeriod` in seconds
     * @param disputePeriod Dispute period in seconds
     */
    function setDisputePeriod(uint64 disputePeriod) external;

    /**
     * @notice Set the arbitrator address.
     * @dev Update the arbitrator to `_arbitrator`
     * @param arbitrator The address of the arbitration contract or party
     */
    function setArbitrator(address arbitrator) external;

    /**
     * @notice Set the dispute deposit required to create a dispute.
     * @dev Update the dispute deposit to `_disputeDeposit` Graph Tokens
     * @param disputeDeposit The dispute deposit in Graph Tokens
     */
    function setDisputeDeposit(uint256 disputeDeposit) external;

    /**
     * @notice Set the percent reward that the fisherman gets when slashing occurs.
     * @dev Update the reward percentage to `_percentage`
     * @param fishermanRewardCut_ Reward as a percentage of indexer stake
     */
    function setFishermanRewardCut(uint32 fishermanRewardCut_) external;

    /**
     * @notice Set the maximum percentage that can be used for slashing indexers.
     * @param maxSlashingCut_ Max percentage slashing for disputes
     */
    function setMaxSlashingCut(uint32 maxSlashingCut_) external;

    /**
     * @notice Set the subgraph service address.
     * @dev Update the subgraph service to `_subgraphService`
     * @param subgraphService The address of the subgraph service contract
     */
    function setSubgraphService(address subgraphService) external;

    // -- Dispute --

    /**
     * @notice Create a query dispute for the arbitrator to resolve.
     * This function is called by a fisherman and it will pull `disputeDeposit` GRT tokens.
     *
     * * Requirements:
     * - fisherman must have previously approved this contract to pull `disputeDeposit` amount
     *   of tokens from their balance.
     *
     * @param attestationData Attestation bytes submitted by the fisherman
     * @return The dispute id
     */
    function createQueryDispute(bytes calldata attestationData) external returns (bytes32);

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
     * @return The first dispute id
     * @return The second dispute id
     */
    function createQueryDisputeConflict(
        bytes calldata attestationData1,
        bytes calldata attestationData2
    ) external returns (bytes32, bytes32);

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
     * @return The dispute id
     */
    function createIndexingDispute(address allocationId, bytes32 poi) external returns (bytes32);

    /**
     * @notice Create a legacy dispute.
     * This disputes can be created to settle outstanding slashing amounts with an indexer that has been
     * "legacy slashed" during or shortly after the transition period. See {HorizonStakingExtension.legacySlash}
     * for more details.
     *
     * Note that this type of dispute:
     * - can only be created by the arbitrator
     * - does not require a bond
     * - is automatically accepted when created
     *
     * Additionally, note that this type of disputes allow the arbitrator to directly set the slash and rewards
     * amounts, bypassing the usual mechanisms that impose restrictions on those. This is done to give arbitrators
     * maximum flexibility to ensure outstanding slashing amounts are settled fairly. This function needs to be removed
     * after the transition period.
     *
     * Requirements:
     * - Indexer must have been legacy slashed during or shortly after the transition period
     * - Indexer must have provisioned funds to the Subgraph Service
     *
     * @param allocationId The allocation to dispute
     * @param fisherman The fisherman address to be credited with the rewards
     * @param tokensSlash The amount of tokens to slash
     * @param tokensRewards The amount of tokens to reward the fisherman
     * @return The dispute id
     */
    function createLegacyDispute(
        address allocationId,
        address fisherman,
        uint256 tokensSlash,
        uint256 tokensRewards
    ) external returns (bytes32);

    // -- Arbitrator --

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
    function acceptDispute(bytes32 disputeId, uint256 tokensSlash) external;

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
    ) external;

    /**
     * @notice The arbitrator rejects a dispute as being invalid.
     * Note that conflicting query disputes cannot be rejected.
     * @dev Reject a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be rejected
     */
    function rejectDispute(bytes32 disputeId) external;

    /**
     * @notice The arbitrator draws dispute.
     * Note that drawing a conflicting query dispute should not be possible however it is allowed
     * to give arbitrators greater flexibility when resolving disputes.
     * @dev Ignore a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be disregarded
     */
    function drawDispute(bytes32 disputeId) external;

    /**
     * @notice Once the dispute period ends, if the dispute status remains Pending,
     * the fisherman can cancel the dispute and get back their initial deposit.
     * Note that cancelling a conflicting query dispute will also cancel the related dispute.
     * @dev Cancel a dispute with Id `disputeId`
     * @param disputeId Id of the dispute to be cancelled
     */
    function cancelDispute(bytes32 disputeId) external;

    // -- Getters --

    /**
     * @notice Get the fisherman reward cut.
     * @return Fisherman reward cut in percentage (ppm)
     */
    function getFishermanRewardCut() external view returns (uint32);

    /**
     * @notice Get the dispute period.
     * @return Dispute period in seconds
     */
    function getDisputePeriod() external view returns (uint64);

    /**
     * @notice Return whether a dispute exists or not.
     * @dev Return if dispute with Id `disputeId` exists
     * @param disputeId True if dispute already exists
     * @return True if dispute already exists
     */
    function isDisputeCreated(bytes32 disputeId) external view returns (bool);

    /**
     * @notice Get the message hash that a indexer used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @dev Return the message hash used to sign the receipt
     * @param receipt Receipt returned by indexer and submitted by fisherman
     * @return Message hash used to sign the receipt
     */
    function encodeReceipt(Attestation.Receipt memory receipt) external view returns (bytes32);

    /**
     * @notice Returns the indexer that signed an attestation.
     * @param attestation Attestation
     * @return indexer address
     */
    function getAttestationIndexer(Attestation.State memory attestation) external view returns (address);

    /**
     * @notice Get the stake snapshot for an indexer.
     * @param indexer The indexer address
     * @return The stake snapshot
     */
    function getStakeSnapshot(address indexer) external view returns (uint256);

    /**
     * @notice Checks if two attestations are conflicting
     * @param attestation1 The first attestation
     * @param attestation2 The second attestation
     * @return Whether the attestations are conflicting
     */
    function areConflictingAttestations(
        Attestation.State memory attestation1,
        Attestation.State memory attestation2
    ) external pure returns (bool);
}
