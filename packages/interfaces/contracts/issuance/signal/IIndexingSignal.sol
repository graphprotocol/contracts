// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IIndexingSignal
 * @author Edge & Node
 * @notice Interface for the IndexingSignal contract that manages indexing signal positions.
 *
 * @dev Indexing Signal allows users to lock GRT as signal for specific subgraph deployments.
 * The protocol mints new GRT proportional to signal, funding Recurring Collection Agreements (RCAs)
 * between IS (as payer) and indexers.
 *
 * Uses a virtual escrow model: no GRT is physically deposited or held as escrow. Escrow "balances"
 * are computed from accumulators and represent accumulated uncollected issuance. GRT is minted only
 * at the moment of collection.
 *
 * Two layers:
 * - Signal layer: per-depositor positions and indexer set preferences
 * - Escrow layer: per-(subgraph, indexer) agreement escrows tracking effective signal and accrued issuance
 *
 * Key properties:
 * - 1:1 GRT to signal (no bonding curve)
 * - Lock with immediate withdraw
 * - Self-minting issuance using same per-signal rate as RewardsManager
 * - Per-depositor indexer sets with protocol-enforced minimum count
 * - Per-agreement escrow: effective signal aggregated across depositors, one agreement per (subgraph, indexer)
 * - Virtual escrow: balances computed from accumulators, mint-on-collect
 */
interface IIndexingSignal {
    // -- Structs --

    /**
     * @dev Per-depositor per-subgraph position (signal layer)
     * @param tokens GRT locked by this depositor for this subgraph
     * @param indexerCount Depositor's desired number of indexers
     */
    struct DepositorPosition {
        uint256 tokens;
        uint256 indexerCount;
    }

    /**
     * @dev Per-(subgraph, indexer) agreement escrow (escrow layer)
     * Tracks effective signal and accumulated issuance for one agreement.
     * Signal is the sum of (tokens_d / indexerSetLength_d) across all depositors
     * who have this indexer in their set for this subgraph.
     * @param signal Effective signal backing this agreement
     * @param accIssuanceSnapshot Global accumulator value at last update
     * @param accruedIssuance Accumulated but uncollected issuance
     */
    struct AgreementEscrow {
        uint256 signal;
        uint256 accIssuanceSnapshot;
        uint256 accruedIssuance;
    }

    // -- Events --

    /**
     * @notice Emitted when a depositor locks GRT as indexing signal
     * @param depositor Address of the depositor
     * @param subgraphDeploymentID Subgraph deployment receiving signal
     * @param tokens Amount of GRT locked
     * @param indexerCount Number of indexers requested
     */
    event SignalDeposited(
        address indexed depositor,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 indexerCount
    );

    /**
     * @notice Emitted when a depositor adds GRT to an existing position
     * @param depositor Address of the depositor
     * @param subgraphDeploymentID Subgraph deployment
     * @param tokens Amount of GRT added
     */
    event SignalAdded(address indexed depositor, bytes32 indexed subgraphDeploymentID, uint256 tokens);

    /**
     * @notice Emitted when a depositor withdraws GRT
     * @param depositor Address of the depositor
     * @param subgraphDeploymentID Subgraph deployment
     * @param tokens Amount of GRT withdrawn
     */
    event SignalWithdrawn(address indexed depositor, bytes32 indexed subgraphDeploymentID, uint256 tokens);

    /**
     * @notice Emitted when a depositor changes their desired indexer count
     * @param depositor Address of the depositor
     * @param subgraphDeploymentID Subgraph deployment
     * @param oldCount Previous indexer count
     * @param newCount New indexer count
     */
    event IndexerCountChanged(
        address indexed depositor,
        bytes32 indexed subgraphDeploymentID,
        uint256 oldCount,
        uint256 newCount
    );

    /**
     * @notice Emitted when the indexer set is updated for a depositor's position
     * @param depositor Address of the depositor
     * @param subgraphDeploymentID Subgraph deployment
     * @param indexers New indexer set
     */
    event DepositorIndexerSetUpdated(
        address indexed depositor,
        bytes32 indexed subgraphDeploymentID,
        address[] indexers
    );

    /**
     * @notice Emitted when issuance is collected (minted and distributed)
     * @param subgraphDeploymentID Subgraph deployment
     * @param indexer Address of the indexer (receiver)
     * @param tokens Amount of GRT minted and distributed
     */
    event IssuanceCollected(
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        uint256 tokens
    );

    /**
     * @notice Emitted when an RCA is cancelled and uncollected issuance is settled
     * @param subgraphDeploymentID Subgraph deployment
     * @param indexer Address of the indexer whose RCA was cancelled
     * @param settledTokens Amount of issuance that was settled (never minted)
     */
    event IssuanceSettled(
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        uint256 settledTokens
    );

    /**
     * @notice Emitted when the minimum indexer count is updated
     * @param oldCount Previous minimum
     * @param newCount New minimum
     */
    event MinimumIndexerCountSet(uint256 oldCount, uint256 newCount);

    /**
     * @notice Emitted when a privileged signaler is granted or revoked
     * @param account Address of the account
     * @param privileged Whether the account is privileged
     */
    event PrivilegedSignalerSet(address indexed account, bool privileged);

    // -- Custom Errors --

    /// @notice Thrown when deposit amount is zero
    error DepositAmountZero();

    /// @notice Thrown when indexer count is below the minimum and caller is not privileged
    error IndexerCountBelowMinimum(uint256 requested, uint256 minimum);

    /// @notice Thrown when no existing position found for the operation
    error NoExistingPosition(address depositor, bytes32 subgraphDeploymentID);

    /// @notice Thrown when deposit() is called on an existing position (use addSignal instead)
    error ExistingPosition(address depositor, bytes32 subgraphDeploymentID);

    /// @notice Thrown when withdraw amount exceeds available tokens
    error InsufficientSignal(uint256 requested, uint256 available);

    /// @notice Thrown when indexer set length does not match depositor's indexerCount
    error IndexerSetSizeMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown when a pending agreement hash is not found
    /// @param agreementHash The agreement hash that was not found
    error AgreementNotPrepared(bytes32 agreementHash);

    /// @notice Thrown when the agreement escrow has no signal
    error NoAgreementSignal(bytes32 subgraphDeploymentID, address indexer);

    /**
     * @notice Emitted when an agreement is prepared for contract approval
     * @dev The encodedRCA contains the ABI-encoded RecurringCollectionAgreement struct.
     * Indexers should verify the RCA fields match the agreementHash before accepting.
     * The hash is the EIP712 hash computed by RecurringCollector — IS cannot compute it
     * on-chain, so the operator provides it. A mismatch causes acceptance to fail at RC.
     * @param subgraphDeploymentID Subgraph deployment
     * @param indexer Address of the indexer (serviceProvider in the RCA)
     * @param agreementHash The EIP712 hash of the RCA (computed off-chain via RC)
     * @param encodedRCA ABI-encoded RecurringCollectionAgreement for indexer verification
     */
    event AgreementPrepared(
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        bytes32 agreementHash,
        bytes encodedRCA
    );

    /**
     * @notice Emitted when a prepared agreement hash is cleared
     * @param agreementHash The agreement hash that was cleared
     */
    event AgreementCleared(bytes32 indexed agreementHash);

    // -- Signal Management --

    /**
     * @notice Lock GRT as indexing signal for a subgraph deployment
     * @dev Creates a new position. indexerCount must be >= minimumIndexerCount unless caller is privileged.
     * Transfers GRT from caller to this contract.
     * @param subgraphDeploymentID The subgraph deployment to signal for
     * @param tokens Amount of GRT to lock
     * @param indexerCount Desired number of indexers
     */
    function deposit(bytes32 subgraphDeploymentID, uint256 tokens, uint256 indexerCount) external;

    /**
     * @notice Add more GRT to an existing signal position
     * @dev Position must already exist. Updates agreement escrows for all indexers in the
     * depositor's set to reflect the increased signal.
     * @param subgraphDeploymentID The subgraph deployment
     * @param tokens Amount of GRT to add
     */
    function addSignal(bytes32 subgraphDeploymentID, uint256 tokens) external;

    /**
     * @notice Withdraw GRT from a signal position
     * @dev Immediately returns tokens to the depositor. Updates agreement escrows for all
     * indexers in the depositor's set to reflect the reduced signal.
     * @param subgraphDeploymentID The subgraph deployment
     * @param tokens Amount of GRT to withdraw
     */
    function withdraw(bytes32 subgraphDeploymentID, uint256 tokens) external;

    /**
     * @notice Change the desired indexer count for an existing position
     * @dev Must be >= minimumIndexerCount unless caller is privileged.
     * Triggers off-chain re-selection of indexer set.
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexerCount New desired number of indexers
     */
    function setIndexerCount(bytes32 subgraphDeploymentID, uint256 indexerCount) external;

    // -- Indexer Set Management --

    /**
     * @notice Set the protocol-wide minimum indexer count
     * @dev Only callable by governor. Does not retroactively enforce on existing positions.
     * @param count New minimum indexer count
     */
    function setMinimumIndexerCount(uint256 count) external;

    /**
     * @notice Grant or revoke privileged signaler status
     * @dev Privileged signalers can set indexerCount below the minimum.
     * Only callable by governor.
     * @param account Address to grant/revoke
     * @param privileged Whether to grant (true) or revoke (false)
     */
    function setPrivilegedSignaler(address account, bool privileged) external;

    /**
     * @notice Register the matched indexer set for a depositor's position
     * @dev Called by authorized off-chain role. indexers.length must equal the depositor's indexerCount.
     * Updates agreement escrows: removes depositor's signal contribution from old indexers,
     * adds to new indexers.
     * @param depositor The depositor whose set is being updated
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexers Array of indexer addresses in the matched set
     */
    function setDepositorIndexerSet(
        address depositor,
        bytes32 subgraphDeploymentID,
        address[] calldata indexers
    ) external;

    // -- Contract Approver (Agreement Preparation) --

    /**
     * @notice Prepare an agreement for contract-based RCA approval.
     * @dev Only callable by INDEXER_SET_OPERATOR_ROLE. The operator constructs the full
     * RCA off-chain, computes its EIP712 hash via RecurringCollector, and registers both
     * here. IS stores the hash for the isAuthorizedAgreement callback and emits the full
     * RCA details in the AgreementPrepared event so indexers can verify on-chain.
     *
     * Validates that the (subgraph, indexer) agreement escrow has non-zero signal.
     * The indexer later accepts by passing the same RCA to acceptIndexingAgreementFromContract.
     * RecurringCollector calls back isAuthorizedAgreement(hash) to verify it was prepared.
     *
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer for this agreement (serviceProvider in the RCA)
     * @param agreementHash The EIP712 hash of the RCA (computed off-chain via RC)
     * @param encodedRCA ABI-encoded RecurringCollectionAgreement struct
     */
    function prepareAgreement(
        bytes32 subgraphDeploymentID,
        address indexer,
        bytes32 agreementHash,
        bytes calldata encodedRCA
    ) external;

    /**
     * @notice Clear a prepared agreement hash after it has been accepted or is no longer needed.
     * @dev Only callable by INDEXER_SET_OPERATOR_ROLE. Frees storage for accepted/stale agreements.
     * @param agreementHash The agreement hash to clear
     */
    function clearPreparedAgreement(bytes32 agreementHash) external;

    // -- Collection (Virtual Escrow) --

    /**
     * @notice Settle uncollected issuance when an RCA is cancelled
     * @dev Snapshots accrued issuance and zeroes it out, making it uncollectable.
     * Signal remains in the escrow for new agreement assignments.
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer whose RCA was cancelled
     */
    function onRCACancelled(
        bytes32 subgraphDeploymentID,
        address indexer
    ) external;

    /**
     * @notice Update the global issuance accumulator
     * @dev Must be called before total signal changes to snapshot accrued issuance.
     * @return Current accumulated issuance per signal
     */
    function updateAccIssuancePerSignal() external returns (uint256);

    // -- Views --

    /**
     * @notice Get total indexing signal for a subgraph
     * @param subgraphDeploymentID The subgraph deployment
     * @return Total GRT locked as signal
     */
    function getSubgraphSignal(bytes32 subgraphDeploymentID) external view returns (uint256);

    /**
     * @notice Get a depositor's position for a subgraph
     * @param depositor The depositor address
     * @param subgraphDeploymentID The subgraph deployment
     * @return The depositor's position
     */
    function getDepositorPosition(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view returns (DepositorPosition memory);

    /**
     * @notice Get the matched indexer set for a depositor's position
     * @param depositor The depositor address
     * @param subgraphDeploymentID The subgraph deployment
     * @return Array of indexer addresses
     */
    function getDepositorIndexerSet(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view returns (address[] memory);

    /**
     * @notice Get the virtual escrow balance for a (subgraph, indexer) agreement
     * @dev Computed from the agreement escrow accumulator. Represents uncollected issuance.
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer address
     * @return Virtual balance (collectable amount)
     */
    function getVirtualBalance(
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view returns (uint256);

    /**
     * @notice Get the agreement escrow state for a (subgraph, indexer) pair
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer address
     * @return The agreement escrow state
     */
    function getAgreementEscrow(
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view returns (AgreementEscrow memory);

    /**
     * @notice Get total indexing signal across all subgraphs
     * @return Total GRT locked as indexing signal
     */
    function getTotalSignal() external view returns (uint256);

    /**
     * @notice Get the current accumulated issuance per signal
     * @return Accumulated issuance per signal (includes pending since last update)
     */
    function getAccIssuancePerSignal() external view returns (uint256);

    /**
     * @notice Get the minimum indexer count
     * @return Protocol-enforced minimum
     */
    function getMinimumIndexerCount() external view returns (uint256);

    /**
     * @notice Check if an account is a privileged signaler
     * @param account The address to check
     * @return True if privileged
     */
    function isPrivilegedSignaler(address account) external view returns (bool);
}
