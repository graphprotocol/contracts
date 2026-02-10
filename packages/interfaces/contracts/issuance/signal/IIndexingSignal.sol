// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title IIndexingSignal
 * @author Edge & Node
 * @notice Interface for the IndexingSignal contract that manages indexing signal positions.
 *
 * @dev Indexing Signal allows users to lock GRT as signal for specific subgraph deployments.
 * The protocol mints new GRT proportional to signal, funding Recurring Collection Agreements (RCAs)
 * between signal depositors and indexers via PaymentsEscrow.
 *
 * Key properties:
 * - 1:1 GRT to signal (no bonding curve)
 * - Lock with immediate withdraw
 * - Self-minting issuance using same per-signal rate as RewardsManager
 * - Per-depositor indexer sets with protocol-enforced minimum count
 * - Equal issuance split across matched indexer set
 */
interface IIndexingSignal {
    // -- Structs --

    /**
     * @dev Per-subgraph aggregated signal pool
     * @param totalTokens Total GRT locked as signal for this subgraph
     * @param accIssuancePerSignalSnapshot Snapshot of global accumulator at last update
     * @param accIssuanceForSubgraph Total accumulated issuance for this subgraph
     */
    struct SignalPool {
        uint256 totalTokens;
        uint256 accIssuancePerSignalSnapshot;
        uint256 accIssuanceForSubgraph;
    }

    /**
     * @dev Per-depositor per-subgraph position
     * @param tokens GRT locked by this depositor for this subgraph
     * @param accIssuanceSnapshot Snapshot of global accumulator for pending issuance calculation
     * @param indexerCount Depositor's desired number of indexers
     */
    struct DepositorPosition {
        uint256 tokens;
        uint256 accIssuanceSnapshot;
        uint256 indexerCount;
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
     * @notice Emitted when issuance is minted and deposited to escrow
     * @param depositor Address of the depositor (payer)
     * @param subgraphDeploymentID Subgraph deployment
     * @param indexer Address of the indexer (receiver)
     * @param tokens Amount of GRT minted
     */
    event IssuanceMinted(
        address indexed depositor,
        bytes32 indexed subgraphDeploymentID,
        address indexed indexer,
        uint256 tokens
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

    /// @notice Thrown when withdraw amount exceeds available tokens
    error InsufficientSignal(uint256 requested, uint256 available);

    /// @notice Thrown when indexer set length does not match depositor's indexerCount
    error IndexerSetSizeMismatch(uint256 provided, uint256 expected);

    /// @notice Thrown when indexer is not in the depositor's matched set
    error IndexerNotInSet(address indexer);

    /// @notice Thrown when the indexer set is empty (no indexers matched yet)
    error IndexerSetEmpty();

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
     * @dev Position must already exist. Increases signal proportionally.
     * @param subgraphDeploymentID The subgraph deployment
     * @param tokens Amount of GRT to add
     */
    function addSignal(bytes32 subgraphDeploymentID, uint256 tokens) external;

    /**
     * @notice Withdraw GRT from a signal position
     * @dev Immediately returns tokens to the depositor. Reduces signal proportionally.
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
     * Creates RCAs for added indexers, cancels RCAs for removed indexers.
     * @param depositor The depositor whose set is being updated
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexers Array of indexer addresses in the matched set
     */
    function setDepositorIndexerSet(
        address depositor,
        bytes32 subgraphDeploymentID,
        address[] calldata indexers
    ) external;

    // -- Issuance --

    /**
     * @notice Mint pending issuance for a depositor-subgraph-indexer tuple and deposit to escrow
     * @dev Mints 1/N of depositor's total pending issuance (N = indexerSet.length).
     * Called by SubgraphService during collect flow.
     * @param depositor The depositor (payer in escrow)
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer (receiver in escrow)
     * @return issuedTokens Amount of GRT minted and deposited to escrow
     */
    function mintPendingIssuance(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external returns (uint256 issuedTokens);

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
     * @notice Get pending (unminted) issuance for a depositor-subgraph pair
     * @param depositor The depositor address
     * @param subgraphDeploymentID The subgraph deployment
     * @return Total pending issuance across all indexers
     */
    function getPendingIssuance(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view returns (uint256);

    /**
     * @notice Get pending issuance for a specific depositor-indexer pair (1/N of total)
     * @param depositor The depositor address
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer address
     * @return Pending issuance for this indexer
     */
    function getPendingIssuanceForIndexer(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view returns (uint256);

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
