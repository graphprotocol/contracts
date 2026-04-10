// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { IIndexingSignal } from "@graphprotocol/interfaces/contracts/issuance/signal/IIndexingSignal.sol";
import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { IGraphToken } from "../common/IGraphToken.sol";

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
 * Two layers:
 * - Signal layer: per-depositor positions and indexer set preferences
 * - Escrow layer: per-(subgraph, indexer) agreement escrows with aggregated effective signal
 *
 * When depositors' signal or indexer sets change, the affected agreement escrows are updated:
 * accrued issuance is snapshotted, then the effective signal is adjusted.
 *
 * Key invariant: RM_minted + IS_minted = issuancePerBlock * blocks
 * This holds because both use the same accIssuancePerSignal rate with totalSignal as denominator,
 * but RM multiplies by curation signal and IS multiplies by indexing signal.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any bugs. We might have an active bug bounty program.
 */
contract IndexingSignal is BaseUpgradeable, IIndexingSignal, IContractApprover {
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
        /// @notice Per-subgraph total signal (GRT locked)
        mapping(bytes32 => uint256) subgraphSignal;
        /// @notice Per-depositor per-subgraph positions (signal layer)
        mapping(address => mapping(bytes32 => DepositorPosition)) positions;
        /// @notice Per-depositor per-subgraph indexer sets
        mapping(address => mapping(bytes32 => address[])) indexerSets;
        /// @notice Privileged signalers that can bypass minimum indexer count
        mapping(address => bool) privilegedSignalers;
        /// @notice Per-(subgraph, indexer) agreement escrows (escrow layer)
        mapping(bytes32 => mapping(address => AgreementEscrow)) agreementEscrows;
        /// @notice Prepared agreement hashes for contract-based RCA approval.
        /// Set by prepareAgreement(), checked by isAuthorizedAgreement() callback from RecurringCollector.
        mapping(bytes32 agreementHash => bool prepared) pendingAgreements;
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
     * @dev Sets immutable references to GraphToken, RewardsManager, Curation, EscrowRouter, and GraphPayments.
     * @param graphToken Address of the Graph Token contract
     * @param rewardsManager Address of the RewardsManager contract
     * @param curation Address of the Curation contract
     * @param escrowRouter Address of the EscrowRouter contract
     * @param graphPayments Address of the GraphPayments contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        address graphToken,
        address rewardsManager,
        address curation,
        address escrowRouter,
        address graphPayments
    ) BaseUpgradeable(IGraphToken(graphToken)) {
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
    function initialize(address governor, uint256 minimumIndexerCount_) external virtual initializer {
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
        return
            interfaceId == type(IIndexingSignal).interfaceId ||
            interfaceId == type(IContractApprover).interfaceId ||
            super.supportsInterface(interfaceId);
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
            require(
                !(indexerCount < $.minimumIndexerCount),
                IndexerCountBelowMinimum(indexerCount, $.minimumIndexerCount)
            );
        }

        // Update global accumulator before signal changes
        _updateAccIssuancePerSignal($);

        // Create depositor position (no indexer set yet — set later by operator)
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens == 0, ExistingPosition(msg.sender, subgraphDeploymentID));
        pos.tokens = tokens;
        pos.indexerCount = indexerCount;

        // Update totals
        $.subgraphSignal[subgraphDeploymentID] += tokens;
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

        // Update global accumulator
        _updateAccIssuancePerSignal($);

        // Update agreement escrows for this depositor's indexers
        // Use floor(newTotal/n) - floor(oldTotal/n) to avoid rounding drift
        address[] storage indexerSet = $.indexerSets[msg.sender][subgraphDeploymentID];
        uint256 oldTokens = pos.tokens;
        pos.tokens = oldTokens + tokens;
        if (indexerSet.length > 0) {
            uint256 n = indexerSet.length;
            uint256 addedSignalPerIndexer = (pos.tokens / n) - (oldTokens / n);
            for (uint256 i = 0; i < indexerSet.length; ++i) {
                _snapshotAndUpdateSignal($, subgraphDeploymentID, indexerSet[i], addedSignalPerIndexer, true);
            }
        }

        // Update totals
        $.subgraphSignal[subgraphDeploymentID] += tokens;
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
        require(!(tokens > pos.tokens), InsufficientSignal(tokens, pos.tokens));

        // Update global accumulator before signal changes
        _updateAccIssuancePerSignal($);

        // Update agreement escrows for this depositor's indexers
        // Use floor(oldTotal/n) - floor(newTotal/n) to avoid rounding drift
        address[] storage indexerSet = $.indexerSets[msg.sender][subgraphDeploymentID];
        uint256 oldTokens = pos.tokens;
        pos.tokens = oldTokens - tokens;
        if (indexerSet.length > 0) {
            uint256 n = indexerSet.length;
            uint256 removedSignalPerIndexer = (oldTokens / n) - (pos.tokens / n);
            for (uint256 i = 0; i < indexerSet.length; ++i) {
                _snapshotAndUpdateSignal($, subgraphDeploymentID, indexerSet[i], removedSignalPerIndexer, false);
            }
        }

        // Clean up stale state on full withdrawal
        if (pos.tokens == 0) {
            delete $.indexerSets[msg.sender][subgraphDeploymentID];
        }

        // Update totals
        $.subgraphSignal[subgraphDeploymentID] -= tokens;
        $.totalIndexingSignal -= tokens;

        // Transfer GRT back to depositor
        require(GRAPH_TOKEN.transfer(msg.sender, tokens));

        REWARDS_MANAGER.onSubgraphSignalUpdate(subgraphDeploymentID);

        emit SignalWithdrawn(msg.sender, subgraphDeploymentID, tokens);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function setIndexerCount(bytes32 subgraphDeploymentID, uint256 indexerCount) external override whenNotPaused {
        IndexingSignalData storage $ = _getStorage();
        DepositorPosition storage pos = $.positions[msg.sender][subgraphDeploymentID];
        require(pos.tokens > 0, NoExistingPosition(msg.sender, subgraphDeploymentID));

        if (!$.privilegedSignalers[msg.sender]) {
            require(
                !(indexerCount < $.minimumIndexerCount),
                IndexerCountBelowMinimum(indexerCount, $.minimumIndexerCount)
            );
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

        // Update accumulator before changing escrow signal
        _updateAccIssuancePerSignal($);

        uint256 depositorTokens = pos.tokens;
        address[] storage oldSet = $.indexerSets[depositor][subgraphDeploymentID];

        // Remove depositor's signal contribution from old indexers' agreement escrows
        if (oldSet.length > 0) {
            uint256 oldSignalPerIndexer = depositorTokens / oldSet.length;
            for (uint256 i = 0; i < oldSet.length; ++i) {
                _snapshotAndUpdateSignal($, subgraphDeploymentID, oldSet[i], oldSignalPerIndexer, false);
            }
        }

        // Add depositor's signal contribution to new indexers' agreement escrows
        if (indexers.length > 0) {
            uint256 newSignalPerIndexer = depositorTokens / indexers.length;
            for (uint256 i = 0; i < indexers.length; ++i) {
                _snapshotAndUpdateSignal($, subgraphDeploymentID, indexers[i], newSignalPerIndexer, true);
            }
        }

        $.indexerSets[depositor][subgraphDeploymentID] = indexers;

        emit DepositorIndexerSetUpdated(depositor, subgraphDeploymentID, indexers);
    }

    // -- Contract Approver (IContractApprover + Agreement Preparation) --

    /**
     * @inheritdoc IContractApprover
     * @dev Called by RecurringCollector.acceptFromContract() during agreement acceptance.
     * Returns the magic value only if the agreement hash was previously prepared via prepareAgreement().
     */
    function isAuthorizedAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        IndexingSignalData storage $ = _getStorage();
        if ($.pendingAgreements[agreementHash]) {
            return IContractApprover.isAuthorizedAgreement.selector;
        }
        revert AgreementNotPrepared(agreementHash);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function prepareAgreement(
        bytes32 subgraphDeploymentID,
        address indexer,
        bytes32 agreementHash,
        bytes calldata encodedRCA
    ) external override onlyRole(INDEXER_SET_OPERATOR_ROLE) whenNotPaused {
        IndexingSignalData storage $ = _getStorage();

        // Validate: agreement escrow has non-zero signal for this (subgraph, indexer) pair
        AgreementEscrow storage escrow = $.agreementEscrows[subgraphDeploymentID][indexer];
        require(escrow.signal > 0, NoAgreementSignal(subgraphDeploymentID, indexer));

        // Store the pending agreement hash
        $.pendingAgreements[agreementHash] = true;

        emit AgreementPrepared(subgraphDeploymentID, indexer, agreementHash, encodedRCA);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function clearPreparedAgreement(bytes32 agreementHash) external override onlyRole(INDEXER_SET_OPERATOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();
        delete $.pendingAgreements[agreementHash];
        emit AgreementCleared(agreementHash);
    }

    // -- IPaymentsEscrow Implementation (Virtual Escrow) --

    /**
     * @notice Collect via the escrow interface without context. Reverts - context is required
     * for virtual escrow to resolve the subgraph deployment.
     */
    // solhint-disable-next-line use-natspec
    function collect(IGraphPayments.PaymentTypes, address, address, uint256, address, uint256, address) external pure {
        revert CollectionContextRequired();
    }

    /**
     * @notice Collect via the escrow interface with collection context.
     * Called by EscrowRouter when this contract is the escrow override for a payer.
     * Interprets collectionContext as subgraphDeploymentID.
     * Mints GRT and distributes via GraphPayments (protocol tax, data service cut, delegation).
     * @param paymentType The type of payment being collected
     * @param receiver The indexer receiving the payment
     * @param tokens The amount of tokens to collect
     * @param dataService The data service address for payment distribution
     * @param dataServiceCut The data service cut percentage
     * @param receiverDestination The destination address for the receiver
     * @param collectionContext The subgraph deployment ID encoded as bytes32
     */
    // solhint-disable-next-line use-natspec
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        address,
        address receiver,
        uint256 tokens,
        address dataService,
        uint256 dataServiceCut,
        address receiverDestination,
        bytes32 collectionContext
    ) external whenNotPaused {
        require(msg.sender == ESCROW_ROUTER, UnauthorizedEscrowCaller(msg.sender));

        // collectionContext is the subgraphDeploymentID, receiver is the indexer
        uint256 collectedTokens = _collectVirtual(collectionContext, receiver, tokens);

        if (collectedTokens > 0) {
            // Mint GRT to this contract, then distribute via GraphPayments
            GRAPH_TOKEN.mint(address(this), collectedTokens);
            GRAPH_TOKEN.approve(address(GRAPH_PAYMENTS), collectedTokens);
            GRAPH_PAYMENTS.collect(
                paymentType,
                receiver,
                collectedTokens,
                dataService,
                dataServiceCut,
                receiverDestination
            );
        }

        emit IssuanceCollected(collectionContext, receiver, collectedTokens);
    }

    /**
     * @notice Get virtual escrow balance for a (payer, collector, receiver) tuple.
     * Without a subgraph context, we cannot compute a meaningful balance.
     * Callers should use getVirtualBalance() for precise queries.
     * @return Always returns 0 since subgraph context is required for meaningful balance
     */
    // solhint-disable-next-line use-natspec
    function getBalance(address, address, address) external pure returns (uint256) {
        return 0;
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function onRCACancelled(
        bytes32 subgraphDeploymentID,
        address indexer
    ) external override whenNotPaused onlyRole(INDEXER_SET_OPERATOR_ROLE) {
        IndexingSignalData storage $ = _getStorage();

        // Update accumulator to current block
        _updateAccIssuancePerSignal($);

        AgreementEscrow storage escrow = $.agreementEscrows[subgraphDeploymentID][indexer];

        // Calculate what would have been collectible (for the event)
        uint256 settledTokens = _calcVirtualBalance(escrow, $.accIssuancePerSignal);

        // Zero out accrued issuance and advance snapshot — uncollected issuance is never minted
        escrow.accruedIssuance = 0;
        escrow.accIssuanceSnapshot = $.accIssuancePerSignal;

        emit IssuanceSettled(subgraphDeploymentID, indexer, settledTokens);
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
        return _getStorage().subgraphSignal[subgraphDeploymentID];
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
    function getVirtualBalance(bytes32 subgraphDeploymentID, address indexer) external view override returns (uint256) {
        IndexingSignalData storage $ = _getStorage();
        uint256 currentAcc = $.accIssuancePerSignal + _getNewIssuancePerSignal($);
        return _calcVirtualBalance($.agreementEscrows[subgraphDeploymentID][indexer], currentAcc);
    }

    /**
     * @inheritdoc IIndexingSignal
     */
    function getAgreementEscrow(
        bytes32 subgraphDeploymentID,
        address indexer
    ) external view override returns (AgreementEscrow memory) {
        return _getStorage().agreementEscrows[subgraphDeploymentID][indexer];
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
     * @notice Shared virtual escrow collection logic
     * @dev Computes available balance from the
     * agreement escrow, determines collection amount, and updates escrow state.
     * Does NOT mint or distribute - caller is responsible for that.
     * @param subgraphDeploymentID The subgraph deployment to collect from
     * @param indexer The indexer whose agreement escrow to collect from
     * @param amount The requested collection amount (0 for all available)
     * @return collectedTokens The amount of tokens collected from virtual balance
     */
    function _collectVirtual(
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 amount
    ) internal returns (uint256 collectedTokens) {
        IndexingSignalData storage $ = _getStorage();

        // Update accumulator to current block
        _updateAccIssuancePerSignal($);

        AgreementEscrow storage escrow = $.agreementEscrows[subgraphDeploymentID][indexer];

        // Compute available virtual balance
        uint256 available = _calcVirtualBalance(escrow, $.accIssuancePerSignal);

        // Determine collection amount
        collectedTokens = amount == 0 ? available : (amount < available ? amount : available);

        if (collectedTokens > 0) {
            // Update escrow: subtract collected, advance snapshot
            escrow.accruedIssuance = available - collectedTokens;
            escrow.accIssuanceSnapshot = $.accIssuancePerSignal;
        }
    }

    /**
     * @notice Calculate virtual balance for an agreement escrow
     * @dev Calculate virtual balance for an agreement escrow at a given accumulator value.
     * @param escrow The agreement escrow to calculate balance for
     * @param currentAccIssuancePerSignal The current accumulated issuance per signal value
     * @return Virtual balance = accruedIssuance + (signal * accumulator delta / scaling)
     */
    function _calcVirtualBalance(
        AgreementEscrow storage escrow,
        uint256 currentAccIssuancePerSignal
    ) internal view returns (uint256) {
        uint256 newIssuance = 0;
        if (escrow.signal > 0 && currentAccIssuancePerSignal > escrow.accIssuanceSnapshot) {
            uint256 delta = currentAccIssuancePerSignal - escrow.accIssuanceSnapshot;
            newIssuance = (escrow.signal * delta) / FIXED_POINT_SCALING_FACTOR;
        }
        return escrow.accruedIssuance + newIssuance;
    }

    /**
     * @notice Snapshot accrued issuance for an agreement escrow and adjust its signal
     * @dev Must be called after _updateAccIssuancePerSignal().
     * @param $ Storage pointer
     * @param subgraphDeploymentID The subgraph deployment
     * @param indexer The indexer
     * @param signalDelta Amount of effective signal to add or remove
     * @param isAdd True to add signal, false to remove
     */
    // solhint-disable-next-line use-natspec
    function _snapshotAndUpdateSignal(
        IndexingSignalData storage $,
        bytes32 subgraphDeploymentID,
        address indexer,
        uint256 signalDelta,
        bool isAdd
    ) internal {
        AgreementEscrow storage escrow = $.agreementEscrows[subgraphDeploymentID][indexer];

        // Snapshot: accrue issuance at current signal level before changing it
        if (escrow.signal > 0 && $.accIssuancePerSignal > escrow.accIssuanceSnapshot) {
            uint256 delta = $.accIssuancePerSignal - escrow.accIssuanceSnapshot;
            escrow.accruedIssuance += (escrow.signal * delta) / FIXED_POINT_SCALING_FACTOR;
        }
        escrow.accIssuanceSnapshot = $.accIssuancePerSignal;

        // Adjust signal
        if (isAdd) {
            escrow.signal += signalDelta;
        } else {
            escrow.signal -= signalDelta;
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
     * @dev Get the ERC-7201 namespaced storage
     */
    function _getStorage() private pure returns (IndexingSignalData storage $) {
        bytes32 slot = INDEXING_SIGNAL_STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }
}
