// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { IIndexingSignal } from "@graphprotocol/interfaces/contracts/issuance/signal/IIndexingSignal.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title IndexingSignal
 * @author Edge & Node
 * @notice Manages indexing signal positions that direct protocol issuance toward indexing payments.
 *
 * @dev Users lock GRT as signal for specific subgraph deployments (1:1, no bonding curve)
 * and can withdraw immediately. The contract self-mints issuance at the same per-signal
 * rate as RewardsManager, using a virtual escrow model where GRT is only minted at
 * collection time.
 *
 * Virtual escrow: no GRT is physically deposited or held as escrow. Escrow "balances" are
 * computed from accumulators and represent accumulated uncollected issuance. The collect()
 * function mints GRT on demand and transfers to the caller for distribution.
 *
 * Key invariant: RM_minted + IS_minted = issuancePerBlock * blocks
 * This holds because both use the same accIssuancePerSignal rate with totalSignal as denominator,
 * but RM multiplies by curation signal and IS multiplies by indexing signal.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract IndexingSignal is BaseUpgradeable, IIndexingSignal {
    // -- Constants --

    /// @notice Precision scaling factor for accumulated issuance calculations
    uint256 private constant FIXED_POINT_SCALING_FACTOR = 1e18;

    /// @notice Role for the off-chain indexer set operator
    bytes32 public constant INDEXER_SET_OPERATOR_ROLE = keccak256("INDEXER_SET_OPERATOR_ROLE");

    // -- Immutable Variables --

    /// @notice The RewardsManager contract (for reading issuance rate and total curation signal)
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardsManager internal immutable REWARDS_MANAGER;

    /// @notice The Curation contract address (for reading curation signal balance)
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable CURATION;

    /// @notice The EscrowRouter contract (authorized caller for escrow collect)
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable ESCROW_ROUTER;

    /// @notice The GraphPayments contract (for standard payment distribution)
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IGraphPayments internal immutable GRAPH_PAYMENTS;

    // -- Storage (ERC-7201) --

    /// @custom:storage-location erc7201:graphprotocol.storage.IndexingSignal
    struct IndexingSignalData {
        /// @notice Global accumulated issuance per signal unit
        uint256 accIssuancePerSignal;
        /// @notice Block number of last accumulator update
        uint256 accIssuancePerSignalLastBlock;
        /// @notice Total GRT locked as indexing signal across all subgraphs
        uint256 totalIndexingSignal;
        /// @notice Protocol-enforced minimum number of indexers per position
        uint256 minimumIndexerCount;
        /// @notice Per-subgraph signal pools
        mapping(bytes32 => SignalPool) pools;
        /// @notice Per-depositor per-subgraph positions
        mapping(address => mapping(bytes32 => DepositorPosition)) positions;
        /// @notice Per-depositor per-subgraph indexer sets (stored separately from position struct)
        mapping(address => mapping(bytes32 => address[])) indexerSets;
        /// @notice Privileged signalers that can bypass minimum indexer count
        mapping(address => bool) privilegedSignalers;
        /// @notice Per-(depositor, subgraph, indexer) collection snapshot.
        /// Tracks accIssuancePerSignal at the time of last collection for each indexer,
        /// enabling independent collection tracking per indexer in the virtual escrow model.
        mapping(address => mapping(bytes32 => mapping(address => uint256))) indexerCollectionSnapshots;
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.IndexingSignal")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INDEXING_SIGNAL_STORAGE_LOCATION =
        0x8c1387b20e42c1a24e6edbc2c3e36f3015e40db24ee2a19a4ed8b5148d39c500;

    // -- Custom Errors --

    /// @notice Thrown when an immutable address constructor argument is zero
    error AddressCannotBeZero();

    /// @notice Thrown when collect is called by an unauthorized address (must be EscrowRouter)
    error UnauthorizedEscrowCaller(address caller);

    /// @notice Thrown when the no-context collect overload is called (not supported for virtual escrow)
    error CollectionContextRequired();

    // -- Constructor --

    /**
     * @notice Constructor for the IndexingSignal contract
     * @dev Sets immutable references to GraphToken, RewardsManager, and Curation.
     * @param graphToken Address of the Graph Token contract
     * @param rewardsManager Address of the RewardsManager contract
     * @param curation Address of the Curation contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        address graphToken,
        address rewardsManager,
        address curation,
        address escrowRouter,
        address graphPayments
    ) BaseUpgradeable(graphToken) {
        require(rewardsManager != address(0), AddressCannotBeZero());
        require(curation != address(0), AddressCannotBeZero());
        require(escrowRouter != address(0), AddressCannotBeZero());
        require(graphPayments != address(0), AddressCannotBeZero());
        REWARDS_MANAGER = IRewardsManager(rewardsManager);
        CURATION = curation;
        ESCROW_ROUTER = escrowRouter;
        GRAPH_PAYMENTS = IGraphPayments(graphPayments);
    }

    // -- Initialization --

    /**
     * @notice Initialize the IndexingSignal contract
     * @param governor Address that will have the GOVERNOR_ROLE
     * @param minimumIndexerCount_ Initial minimum indexer count
     */
    function initialize(
        address governor,
        uint256 minimumIndexerCount_
    ) external virtual initializer {
        __BaseUpgradeable_init(governor);

        // Set up indexer set operator role (admin'd by governor)
        _setRoleAdmin(INDEXER_SET_OPERATOR_ROLE, GOVERNOR_ROLE);

        IndexingSignalData storage $ = _getStorage();
        $.minimumIndexerCount = minimumIndexerCount_;
        $.accIssuancePerSignalLastBlock = block.number;
    }

    // -- ERC165 --

    /**
     * @inheritdoc ERC165Upgradeable
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IIndexingSignal).interfaceId || super.supportsInterface(interfaceId);
    }

    // -- Signal Management --

    /**
     * @inheritdoc IIndexingSignal
     */
    function deposit(
        bytes32 subgraphDeploymentID,
        uint256 tokens,
        uint256 indexerCount
    ) external override whenNotPaused {
        require(tokens > 0, DepositAmountZero());

        IndexingSignalData storage $ = _getStorage();

        // Enforce minimum indexer count (unless privileged)
        if (!$.privilegedSignalers[msg.sender]) {
            require(indexerCount >= $.minimumIndexerCount, IndexerCountBelowMinimum(indexerCount, $.minimumIndexerCount));
        }

        // Update global accumulator before signal changes
        _updateAccIssuancePerSignal($);

        // Update subgraph pool
        _onSignalUpdate($, subgraphDeploymentID);

        // Create depositor position
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        pos.tokens = tokens;
        pos.indexerCount = indexerCount;
        pos.accIssuanceSnapshot = $.accIssuancePerSignal;

        // Update pool totals
        $.pools[subgraphDeploymentID].totalTokens += tokens;
        $.totalIndexingSignal += tokens;

        // Transfer GRT from depositor
        require(GRAPH_TOKEN.transferFrom(msg.sender, address(this), tokens));

        // Notify RewardsManager that signal changed
        REWARDS_MANAGER.onSubgraphSignalUpdate(subgraphDeploymentID);

        emit SignalDeposited(msg.sender, subgraphDeploymentID, tokens, indexerCount);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function addSignal(bytes32 subgraphDeploymentID, uint256 tokens) external override whenNotPaused {
        require(tokens > 0, DepositAmountZero());

        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(msg.sender, subgraphDeploymentID));

        // Update accumulators
        _updateAccIssuancePerSignal($);
        _onSignalUpdate($, subgraphDeploymentID);

        // Settle any pending issuance at the old rate before changing signal
        // (snapshot update handles this)
        pos.accIssuanceSnapshot = $.accIssuancePerSignal;
        pos.tokens += tokens;

        // Update pool totals
        $.pools[subgraphDeploymentID].totalTokens += tokens;
        $.totalIndexingSignal += tokens;

        // Transfer GRT from depositor
        require(GRAPH_TOKEN.transferFrom(msg.sender, address(this), tokens));

        REWARDS_MANAGER.onSubgraphSignalUpdate(subgraphDeploymentID);

        emit SignalAdded(msg.sender, subgraphDeploymentID, tokens);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function withdraw(bytes32 subgraphDeploymentID, uint256 tokens) external override whenNotPaused {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(msg.sender, subgraphDeploymentID));
        require(tokens <= pos.tokens, InsufficientSignal(tokens, pos.tokens));

        // Update accumulators before signal changes
        _updateAccIssuancePerSignal($);
        _onSignalUpdate($, subgraphDeploymentID);

        // Remove tokens from position and pool
        pos.tokens -= tokens;
        pos.accIssuanceSnapshot = $.accIssuancePerSignal;

        $.pools[subgraphDeploymentID].totalTokens -= tokens;
        $.totalIndexingSignal -= tokens;

        // Transfer GRT back to depositor
        require(GRAPH_TOKEN.transfer(msg.sender, tokens));

        REWARDS_MANAGER.onSubgraphSignalUpdate(subgraphDeploymentID);

        emit SignalWithdrawn(msg.sender, subgraphDeploymentID, tokens);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function setIndexerCount(
        bytes32 subgraphDeploymentID,
        uint256 indexerCount
    ) external override whenNotPaused {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(msg.sender, subgraphDeploymentID));

        if (!$.privilegedSignalers[msg.sender]) {
            require(indexerCount >= $.minimumIndexerCount, IndexerCountBelowMinimum(indexerCount, $.minimumIndexerCount));
        }

        uint256 oldCount = pos.indexerCount;
        pos.indexerCount = indexerCount;

        emit IndexerCountChanged(msg.sender, subgraphDeploymentID, oldCount, indexerCount);
    }

    // -- Indexer Set Management (Governor / Operator) --

    /**
     * @inheritdoc IIndexingSignal
     */
    function setMinimumIndexerCount(uint256 count) external override onlyRole(GOVERNOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();
        uint256 oldCount = $.minimumIndexerCount;
        $.minimumIndexerCount = count;
        emit MinimumIndexerCountSet(oldCount, count);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function setPrivilegedSignaler(address account, bool privileged) external override onlyRole(GOVERNOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();
        $.privilegedSignalers[account] = privileged;
        emit PrivilegedSignalerSet(account, privileged);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function setDepositorIndexerSet(
        address depositor,
        bytes32 subgraphDeploymentID,
        address[] calldata indexers
    ) external override onlyRole(INDEXER_SET_OPERATOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(depositor, subgraphDeploymentID));
        require(indexers.length == pos.indexerCount, IndexerSetSizeMismatch(indexers.length, pos.indexerCount));

        // Update accumulator before changing the set
        _updateAccIssuancePerSignal($);

        // Initialize collection snapshots for new indexers to the current accumulator.
        // This ensures newly added indexers can only collect issuance from this point forward.
        for (uint256 i = 0; i < indexers.length; i++) {
            uint256 existingSnapshot = $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexers[i]];
            if (existingSnapshot == 0) {
                $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexers[i]] = $.accIssuancePerSignal;
            }
        }

        $.indexerSets[depositor][subgraphDeploymentID] = indexers;

        emit DepositorIndexerSetUpdated(depositor, subgraphDeploymentID, indexers);
    }

    // -- Collection (Virtual Escrow) --

    /**
     * @inheritdoc IIndexingSignal
     */
    function collect(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 amount
    ) external override whenNotPaused returns (uint256 collectedTokens) {
        collectedTokens = _collectVirtual(depositor, subgraphDeploymentID, indexer, amount);

        if (collectedTokens > 0) {
            // Mint GRT and transfer to caller for distribution
            GRAPH_TOKEN.mint(msg.sender, collectedTokens);
        }

        emit IssuanceCollected(depositor, subgraphDeploymentID, indexer, collectedTokens);
    }

    // -- IPaymentsEscrow Implementation (Virtual Escrow) --

    /**
     * @notice Collect via the escrow interface without context. Reverts — context is required
     * for virtual escrow to resolve the subgraph deployment.
     */
    function collect(
        IGraphPayments.PaymentTypes,
        address,
        address,
        uint256,
        address,
        uint256,
        address
    ) external pure {
        revert CollectionContextRequired();
    }

    /**
     * @notice Collect via the escrow interface with collection context.
     * Called by EscrowRouter when this contract is the escrow override for a payer.
     * Interprets collectionContext as subgraphDeploymentID.
     * Mints GRT and distributes via GraphPayments (protocol tax, data service cut, delegation).
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address payer,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination,
        bytes32 collectionContext
    ) external whenNotPaused {
        require(msg.sender == ESCROW_ROUTER, UnauthorizedEscrowCaller(msg.sender));

        // collectionContext is the subgraphDeploymentID
        uint256 collectedTokens = _collectVirtual(payer, collectionContext, receiver, tokens);

        if (collectedTokens > 0) {
            // Mint GRT to this contract, then distribute via GraphPayments
            GRAPH_TOKEN.mint(address(this), collectedTokens);
            GRAPH_TOKEN.approve(address(GRAPH_PAYMENTS), collectedTokens);
            GRAPH_PAYMENTS.collect(paymentType, receiver, collectedTokens, dataService, dataServiceCut, receiverDestination);
        }

        emit IssuanceCollected(payer, collectionContext, receiver, collectedTokens);
    }

    /**
     * @notice Get virtual escrow balance for a (payer, collector, receiver) tuple.
     * Returns the total virtual balance across all subgraphs for this payer-receiver pair.
     * For precise per-subgraph queries, use getVirtualBalance() instead.
     */
    function getBalance(address, address, address) external pure returns (uint256) {
        // Virtual escrow balance is per-(payer, subgraph, indexer), not per-(payer, collector, receiver).
        // Without a subgraph context, we cannot compute a meaningful balance.
        // Return 0 — callers should use getVirtualBalance() for precise queries.
        return 0;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function onRCACancelled(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external override whenNotPaused {
        // TODO: Access control - only callable by authorized cancellation source
        IndexingSignalData storage $ = _getStorage();

        // Update accumulator to current block
        _updateAccIssuancePerSignal($);

        // Calculate what would have been collectible (for the event)
        uint256 settledTokens = _calcVirtualBalance($, depositor, subgraphDeploymentID, indexer);

        // Advance snapshot to current accumulator — uncollected issuance is never minted
        $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexer] = $.accIssuancePerSignal;

        emit IssuanceSettled(depositor, subgraphDeploymentID, indexer, settledTokens);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function updateAccIssuancePerSignal() external override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        return _updateAccIssuancePerSignal($);
    }

    // -- Views --

    /**
     * @inheritdoc IIndexingSignal
     */
    function getSubgraphSignal(bytes32 subgraphDeploymentID) external view override returns (uint256) {
        return _getStorage().pools[subgraphDeploymentID].totalTokens;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getDepositorPosition(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view override returns (DepositorPosition memory) {
        return _getStorage().positions[depositor][subgraphDeploymentID];
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getDepositorIndexerSet(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view override returns (address[] memory) {
        return _getStorage().indexerSets[depositor][subgraphDeploymentID];
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getVirtualBalance(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        uint256 currentAcc = $.accIssuancePerSignal + _getNewIssuancePerSignal($);
        return _calcVirtualBalanceAt($, depositor, subgraphDeploymentID, indexer, currentAcc);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getPendingIssuance(
        address depositor,
        bytes32 subgraphDeploymentID
    ) external view override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
        uint256 currentAcc = $.accIssuancePerSignal + _getNewIssuancePerSignal($);
        return _calcPendingIssuance(pos, currentAcc);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getTotalSignal() external view override returns (uint256) {
        return _getStorage().totalIndexingSignal;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getAccIssuancePerSignal() external view override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        return $.accIssuancePerSignal + _getNewIssuancePerSignal($);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getMinimumIndexerCount() external view override returns (uint256) {
        return _getStorage().minimumIndexerCount;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function isPrivilegedSignaler(address account) external view override returns (bool) {
        return _getStorage().privilegedSignalers[account];
    }

    // -- Internal Functions --

    /**
     * @dev Shared virtual escrow collection logic. Validates indexer set membership,
     * computes virtual balance, determines collection amount, and updates snapshots.
     * Does NOT mint or distribute — caller is responsible for that.
     * @return collectedTokens The amount of tokens collected from virtual balance
     */
    function _collectVirtual(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 amount
    ) internal returns (uint256 collectedTokens) {
        IndexingSignalData storage $ = _getStorage();

        // Update accumulator to current block
        _updateAccIssuancePerSignal($);

        address[] storage indexerSet = $.indexerSets[depositor][subgraphDeploymentID];
        require(indexerSet.length > 0, IndexerSetEmpty());
        require(_isInIndexerSet(indexerSet, indexer), IndexerNotInSet(indexer));

        // Compute virtual balance for this specific indexer
        uint256 available = _calcVirtualBalance($, depositor, subgraphDeploymentID, indexer);

        // Determine collection amount
        collectedTokens = amount == 0 ? available : (amount < available ? amount : available);

        if (collectedTokens > 0) {
            // Update per-indexer collection snapshot proportionally.
            if (collectedTokens == available) {
                $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexer] = $.accIssuancePerSignal;
            } else {
                // Partial collection: advance snapshot proportionally
                DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
                uint256 indexerSnapshot = $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexer];
                uint256 effectiveSnapshot = indexerSnapshot > pos.accIssuanceSnapshot
                    ? indexerSnapshot
                    : pos.accIssuanceSnapshot;
                uint256 totalDelta = $.accIssuancePerSignal - effectiveSnapshot;
                uint256 consumedDelta = (totalDelta * collectedTokens) / available;
                $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexer] =
                    effectiveSnapshot + consumedDelta;
            }
        }
    }

    /**
     * @dev Calculate new issuance per signal since last update
     */
    function _getNewIssuancePerSignal(IndexingSignalData storage $) internal view returns (uint256) {
        uint256 blocksDelta = block.number - $.accIssuancePerSignalLastBlock;
        if (blocksDelta == 0) return 0;

        uint256 issuancePerBlock = REWARDS_MANAGER.getAllocatedIssuancePerBlock();
        if (issuancePerBlock == 0) return 0;

        // Total signal = curation tokens + indexing tokens
        uint256 curationTokens = GRAPH_TOKEN.balanceOf(CURATION);
        uint256 totalSignal = curationTokens + $.totalIndexingSignal;
        if (totalSignal == 0) return 0;

        return (issuancePerBlock * blocksDelta * FIXED_POINT_SCALING_FACTOR) / totalSignal;
    }

    /**
     * @dev Update the global issuance accumulator to the current block
     */
    function _updateAccIssuancePerSignal(IndexingSignalData storage $) internal returns (uint256) {
        uint256 newIssuance = _getNewIssuancePerSignal($);
        $.accIssuancePerSignal += newIssuance;
        $.accIssuancePerSignalLastBlock = block.number;
        return $.accIssuancePerSignal;
    }

    /**
     * @dev Update subgraph pool snapshot before signal changes
     */
    function _onSignalUpdate(IndexingSignalData storage $, bytes32 subgraphDeploymentID) internal {
        SignalPool storage pool = $.pools[subgraphDeploymentID];

        uint256 accIssuancePerSignalDelta = $.accIssuancePerSignal - pool.accIssuancePerSignalSnapshot;
        uint256 newIssuance = (accIssuancePerSignalDelta * pool.totalTokens) / FIXED_POINT_SCALING_FACTOR;

        pool.accIssuanceForSubgraph += newIssuance;
        pool.accIssuancePerSignalSnapshot = $.accIssuancePerSignal;
    }

    /**
     * @dev Calculate pending issuance for a depositor position
     */
    function _calcPendingIssuance(
        DepositorPosition storage pos,
        uint256 currentAccIssuancePerSignal
    ) internal view returns (uint256) {
        if (pos.tokens == 0) return 0;
        uint256 delta = currentAccIssuancePerSignal - pos.accIssuanceSnapshot;
        return (pos.tokens * delta) / FIXED_POINT_SCALING_FACTOR;
    }

    /**
     * @dev Calculate virtual balance for a (depositor, subgraph, indexer) tuple at the current accumulator
     */
    function _calcVirtualBalance(
        IndexingSignalData storage $,
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) internal view returns (uint256) {
        return _calcVirtualBalanceAt($, depositor, subgraphDeploymentID, indexer, $.accIssuancePerSignal);
    }

    /**
     * @dev Calculate virtual balance for a (depositor, subgraph, indexer) tuple at a given accumulator value.
     * The virtual balance is the per-indexer share (1/N) of issuance accrued since last collection.
     */
    function _calcVirtualBalanceAt(
        IndexingSignalData storage $,
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 currentAccIssuancePerSignal
    ) internal view returns (uint256) {
        DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
        if (pos.tokens == 0) return 0;

        address[] storage indexerSet = $.indexerSets[depositor][subgraphDeploymentID];
        if (indexerSet.length == 0) return 0;
        if (!_isInIndexerSet(indexerSet, indexer)) return 0;

        // The per-indexer collection snapshot tracks where this indexer last collected.
        // The position's accIssuanceSnapshot tracks the depositor's global baseline.
        // The effective baseline is the later of the two (indexer can't collect before position was created).
        uint256 indexerSnapshot = $.indexerCollectionSnapshots[depositor][subgraphDeploymentID][indexer];
        uint256 effectiveSnapshot = indexerSnapshot > pos.accIssuanceSnapshot
            ? indexerSnapshot
            : pos.accIssuanceSnapshot;

        if (currentAccIssuancePerSignal <= effectiveSnapshot) return 0;

        uint256 delta = currentAccIssuancePerSignal - effectiveSnapshot;
        uint256 totalIssuance = (pos.tokens * delta) / FIXED_POINT_SCALING_FACTOR;
        return totalIssuance / indexerSet.length;
    }

    /**
     * @dev Check if an indexer is in the given set
     */
    function _isInIndexerSet(address[] storage indexerSet, address indexer) internal view returns (bool) {
        uint256 length = indexerSet.length;
        for (uint256 i = 0; i < length; i++) {
            if (indexerSet[i] == indexer) return true;
        }
        return false;
    }

    /**
     * @dev Get the ERC-7201 namespaced storage
     */
    function _getStorage() private pure returns (IndexingSignalData storage $) {
        bytes32 slot = INDEXING_SIGNAL_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }
}
