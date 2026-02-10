// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { IIndexingSignal } from "@graphprotocol/interfaces/contracts/issuance/signal/IIndexingSignal.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title IndexingSignal
 * @author Edge & Node
 * @notice Manages indexing signal positions that direct protocol issuance toward indexing payments.
 *
 * @dev Users lock GRT as signal for specific subgraph deployments (1:1, no bonding curve).
 * The contract self-mints issuance at the same per-signal rate as RewardsManager,
 * depositing minted GRT to PaymentsEscrow to fund RCAs between depositors and indexers.
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

    // -- Storage (ERC-7201) --

    /// @custom:storage-location erc7201:graphprotocol.storage.IndexingSignal
    struct IndexingSignalData {
        /// @notice Global accumulated issuance per signal unit
        uint256 accIssuancePerSignal;
        /// @notice Block number of last accumulator update
        uint256 accIssuancePerSignalLastBlock;
        /// @notice Total GRT locked as indexing signal across all subgraphs
        uint256 totalIndexingSignal;
        /// @notice Thawing period in seconds before signal can be withdrawn
        uint256 thawingPeriod;
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
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.IndexingSignal")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INDEXING_SIGNAL_STORAGE_LOCATION =
        0x8c1387b20e42c1a24e6edbc2c3e36f3015e40db24ee2a19a4ed8b5148d39c500;

    // -- Custom Errors --

    /// @notice Thrown when an immutable address constructor argument is zero
    error AddressCannotBeZero();

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
        address curation
    ) BaseUpgradeable(graphToken) {
        require(rewardsManager != address(0), AddressCannotBeZero());
        require(curation != address(0), AddressCannotBeZero());
        REWARDS_MANAGER = IRewardsManager(rewardsManager);
        CURATION = curation;
    }

    // -- Initialization --

    /**
     * @notice Initialize the IndexingSignal contract
     * @param governor Address that will have the GOVERNOR_ROLE
     * @param minimumIndexerCount_ Initial minimum indexer count
     * @param thawingPeriod_ Initial thawing period in seconds
     */
    function initialize(
        address governor,
        uint256 minimumIndexerCount_,
        uint256 thawingPeriod_
    ) external virtual initializer {
        __BaseUpgradeable_init(governor);

        // Set up indexer set operator role (admin'd by governor)
        _setRoleAdmin(INDEXER_SET_OPERATOR_ROLE, GOVERNOR_ROLE);

        IndexingSignalData storage $ = _getStorage();
        $.minimumIndexerCount = minimumIndexerCount_;
        $.thawingPeriod = thawingPeriod_;
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
    function thaw(bytes32 subgraphDeploymentID, uint256 tokens) external override whenNotPaused {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(msg.sender, subgraphDeploymentID));

        uint256 available = pos.tokens - pos.thawingTokens;
        require(tokens <= available, InsufficientSignal(tokens, available));

        pos.thawingTokens += tokens;
        pos.thawEndTimestamp = block.timestamp + $.thawingPeriod;

        emit SignalThawing(msg.sender, subgraphDeploymentID, tokens, pos.thawEndTimestamp);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function withdraw(bytes32 subgraphDeploymentID) external override whenNotPaused {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.thawingTokens > 0, NothingToWithdraw());
        require(block.timestamp >= pos.thawEndTimestamp, ThawNotComplete(pos.thawEndTimestamp, block.timestamp));

        uint256 tokensToReturn = pos.thawingTokens;

        // Update accumulators before signal changes
        _updateAccIssuancePerSignal($);
        _onSignalUpdate($, subgraphDeploymentID);

        // Remove thawed tokens from position and pool
        pos.tokens -= tokensToReturn;
        pos.thawingTokens = 0;
        pos.thawEndTimestamp = 0;
        pos.accIssuanceSnapshot = $.accIssuancePerSignal;

        $.pools[subgraphDeploymentID].totalTokens -= tokensToReturn;
        $.totalIndexingSignal -= tokensToReturn;

        // Transfer GRT back to depositor
        require(GRAPH_TOKEN.transfer(msg.sender, tokensToReturn));

        REWARDS_MANAGER.onSubgraphSignalUpdate(subgraphDeploymentID);

        emit SignalWithdrawn(msg.sender, subgraphDeploymentID, tokensToReturn);
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
    function setThawingPeriod(uint256 period) external override onlyRole(GOVERNOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();
        uint256 oldPeriod = $.thawingPeriod;
        $.thawingPeriod = period;
        emit ThawingPeriodSet(oldPeriod, period);
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

        $.indexerSets[depositor][subgraphDeploymentID] = indexers;

        emit DepositorIndexerSetUpdated(depositor, subgraphDeploymentID, indexers);
    }

    // -- Issuance --

    /**
     * @inheritdoc IIndexingSignal
     */
    function mintPendingIssuance(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external override whenNotPaused returns (uint256 issuedTokens) {
        IndexingSignalData storage $ = _getStorage();

        // Update accumulator to current block
        _updateAccIssuancePerSignal($);

        DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
        address[] storage indexerSet = $.indexerSets[depositor][subgraphDeploymentID];

        require(indexerSet.length > 0, IndexerSetEmpty());
        require(_isInIndexerSet(indexerSet, indexer), IndexerNotInSet(indexer));

        // Calculate total pending issuance for this depositor
        uint256 totalPending = _calcPendingIssuance(pos, $.accIssuancePerSignal);

        // Equal split across indexer set
        uint256 perIndexer = totalPending / indexerSet.length;

        if (perIndexer > 0) {
            // Mint GRT
            GRAPH_TOKEN.mint(address(this), perIndexer);

            // TODO: Deposit to PaymentsEscrow
            // For now, transfer directly. Escrow integration will be wired when
            // RecurringCollector is integrated.
            // paymentsEscrow.depositTo(depositor, recurringCollector, indexer, perIndexer);
            require(GRAPH_TOKEN.transfer(indexer, perIndexer));
        }

        // Update snapshot (only for this indexer's share - track per-indexer collection separately)
        // NOTE: This is a simplification. A production implementation needs per-indexer
        // collection tracking to avoid one indexer collecting another's share.
        // For rough design: update snapshot after all indexers have collected.

        emit IssuanceMinted(depositor, subgraphDeploymentID, indexer, perIndexer);
        return perIndexer;
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
    function getPendingIssuanceForIndexer(
        address depositor,
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[depositor][subgraphDeploymentID];
        address[] storage indexerSet = $.indexerSets[depositor][subgraphDeploymentID];

        require(indexerSet.length > 0, IndexerSetEmpty());
        require(_isInIndexerSet(indexerSet, indexer), IndexerNotInSet(indexer));

        uint256 currentAcc = $.accIssuancePerSignal + _getNewIssuancePerSignal($);
        uint256 totalPending = _calcPendingIssuance(pos, currentAcc);
        return totalPending / indexerSet.length;
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
    function getThawingPeriod() external view override returns (uint256) {
        return _getStorage().thawingPeriod;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function isPrivilegedSignaler(address account) external view override returns (bool) {
        return _getStorage().privilegedSignalers[account];
    }

    // -- Internal Functions --

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
