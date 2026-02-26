// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.33;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IIndexingAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIndexingAgreementManager.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";

import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title IndexingAgreementManager
 * @author Edge & Node
 * @notice Manages escrow funding for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator (implements IIssuanceTarget)
 * 2. Authorizes RCA acceptance via contract callback (implements IContractApprover)
 * 3. Tracks max-next-claim per agreement, funds PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, RecurringCollector, indexer) covers all managed
 * RCAs for that indexer. Other participants can independently use RCAs via the
 * standard ECDSA-signed flow.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract IndexingAgreementManager is BaseUpgradeable, IIssuanceTarget, IContractApprover, IIndexingAgreementManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // -- Immutables --

    /// @notice The PaymentsEscrow contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPaymentsEscrow public immutable PAYMENTS_ESCROW;

    /// @notice The RecurringCollector contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRecurringCollector public immutable RECURRING_COLLECTOR;

    // -- Storage (ERC-7201) --

    /// @custom:storage-location erc7201:graphprotocol.issuance.storage.IndexingAgreementManager
    struct IndexingAgreementManagerStorage {
        /// @notice Authorized agreement hashes — maps hash to agreementId (bytes16(0) = not authorized)
        mapping(bytes32 agreementHash => bytes16) authorizedHashes;
        /// @notice Per-agreement tracking data
        mapping(bytes16 agreementId => AgreementInfo) agreements;
        /// @notice Sum of maxNextClaim for all agreements per indexer
        mapping(address indexer => uint256) requiredEscrow;
        /// @notice Set of agreement IDs per indexer (stored as bytes32 for EnumerableSet)
        mapping(address indexer => EnumerableSet.Bytes32Set) indexerAgreementIds;
        /// @notice Whether a thaw has been initiated for an indexer's escrow
        mapping(address indexer => bool) thawing;
    }

    // solhint-disable-next-line gas-named-return-values
    // keccak256(abi.encode(uint256(keccak256("graphprotocol.issuance.storage.IndexingAgreementManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INDEXING_AGREEMENT_MANAGER_STORAGE_LOCATION =
        0x479ba94faf2fd6cabf7893623bfa7a552c10e95e15de10bc58f1e58f2bb8fb00;

    // -- Constructor --

    /**
     * @notice Constructor for the IndexingAgreementManager contract
     * @param graphToken Address of the Graph Token contract
     * @param paymentsEscrow Address of the PaymentsEscrow contract
     * @param recurringCollector Address of the RecurringCollector contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken, address paymentsEscrow, address recurringCollector) BaseUpgradeable(graphToken) {
        PAYMENTS_ESCROW = IPaymentsEscrow(paymentsEscrow);
        RECURRING_COLLECTOR = IRecurringCollector(recurringCollector);
    }

    // -- Initialization --

    /**
     * @notice Initialize the IndexingAgreementManager contract
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);
    }

    // -- ERC165 --

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IIssuanceTarget).interfaceId ||
            interfaceId == type(IContractApprover).interfaceId ||
            interfaceId == type(IIndexingAgreementManager).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- IIssuanceTarget --

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external virtual override {
        emit IIssuanceTarget.BeforeIssuanceAllocationChange();
    }

    /// @inheritdoc IIssuanceTarget
    /// @dev No-op: IndexingAgreementManager receives tokens via transfer, does not need the allocator address.
    function setIssuanceAllocator(address /* issuanceAllocator */) external virtual override onlyRole(GOVERNOR_ROLE) {}

    // -- IContractApprover --

    /// @inheritdoc IContractApprover
    function isAuthorizedAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        bytes16 agreementId = $.authorizedHashes[agreementHash];
        require(
            agreementId != bytes16(0) && $.agreements[agreementId].exists,
            IndexingAgreementManagerAgreementNotAuthorized(agreementHash)
        );
        return IContractApprover.isAuthorizedAgreement.selector;
    }

    // -- IIndexingAgreementManager: Core Functions --

    /// @inheritdoc IIndexingAgreementManager
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        require(rca.payer == address(this), IndexingAgreementManagerPayerMismatch(rca.payer, address(this)));
        require(rca.serviceProvider != address(0), IndexingAgreementManagerInvalidRCAField("serviceProvider"));
        require(rca.dataService != address(0), IndexingAgreementManagerInvalidRCAField("dataService"));

        IndexingAgreementManagerStorage storage $ = _getStorage();

        agreementId = RECURRING_COLLECTOR.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        require(!$.agreements[agreementId].exists, IndexingAgreementManagerAgreementAlreadyOffered(agreementId));

        // Cancel any in-progress thaw for this indexer (new agreement needs funded escrow)
        if ($.thawing[rca.serviceProvider]) {
            PAYMENTS_ESCROW.cancelThaw(address(RECURRING_COLLECTOR), rca.serviceProvider);
            $.thawing[rca.serviceProvider] = false;
        }

        // Calculate max next claim from RCA parameters (pre-acceptance, so use initial + ongoing)
        uint256 maxNextClaim = rca.maxOngoingTokensPerSecond * rca.maxSecondsPerCollection + rca.maxInitialTokens;

        // Authorize the agreement hash for the IContractApprover callback
        bytes32 agreementHash = RECURRING_COLLECTOR.hashRCA(rca);
        $.authorizedHashes[agreementHash] = agreementId;

        // Store agreement tracking data
        $.agreements[agreementId] = AgreementInfo({
            indexer: rca.serviceProvider,
            deadline: rca.deadline,
            exists: true,
            dataService: rca.dataService,
            pendingUpdateNonce: 0,
            maxNextClaim: maxNextClaim,
            pendingUpdateMaxNextClaim: 0,
            agreementHash: agreementHash,
            pendingUpdateHash: bytes32(0)
        });
        $.indexerAgreementIds[rca.serviceProvider].add(bytes32(agreementId));
        $.requiredEscrow[rca.serviceProvider] += maxNextClaim;

        // Fund the escrow
        _fundEscrow($, rca.serviceProvider);

        emit AgreementOffered(agreementId, rca.serviceProvider, maxNextClaim);
    }

    /// @inheritdoc IIndexingAgreementManager
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        agreementId = rcau.agreementId;
        IndexingAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.exists, IndexingAgreementManagerAgreementNotOffered(agreementId));

        // Calculate pending max next claim from RCAU parameters (conservative: includes initial + ongoing)
        uint256 pendingMaxNextClaim = rcau.maxOngoingTokensPerSecond * rcau.maxSecondsPerCollection +
            rcau.maxInitialTokens;

        // If replacing an existing pending update, remove old pending from requiredEscrow and clean up hash
        if (info.pendingUpdateHash != bytes32(0)) {
            $.requiredEscrow[info.indexer] -= info.pendingUpdateMaxNextClaim;
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Authorize the RCAU hash for the IContractApprover callback
        bytes32 updateHash = RECURRING_COLLECTOR.hashRCAU(rcau);
        $.authorizedHashes[updateHash] = agreementId;

        // Store pending update tracking
        info.pendingUpdateMaxNextClaim = pendingMaxNextClaim;
        info.pendingUpdateNonce = rcau.nonce;
        info.pendingUpdateHash = updateHash;
        $.requiredEscrow[info.indexer] += pendingMaxNextClaim;

        // Fund the escrow
        _fundEscrow($, info.indexer);

        emit AgreementUpdateOffered(agreementId, pendingMaxNextClaim, rcau.nonce);
    }

    /// @inheritdoc IIndexingAgreementManager
    function revokeOffer(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.exists, IndexingAgreementManagerAgreementNotOffered(agreementId));

        // Only revoke un-accepted agreements — accepted ones must be canceled via cancelAgreement
        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);
        require(
            agreement.state == IRecurringCollector.AgreementState.NotAccepted,
            IndexingAgreementManagerAgreementAlreadyAccepted(agreementId)
        );

        address indexer = info.indexer;
        uint256 totalToRemove = info.maxNextClaim + info.pendingUpdateMaxNextClaim;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Clean up storage
        $.requiredEscrow[indexer] -= totalToRemove;
        $.indexerAgreementIds[indexer].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit OfferRevoked(agreementId, indexer);
    }

    /// @inheritdoc IIndexingAgreementManager
    function cancelAgreement(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.exists, IndexingAgreementManagerAgreementNotOffered(agreementId));

        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);

        // Not accepted — use revokeOffer instead
        require(
            agreement.state != IRecurringCollector.AgreementState.NotAccepted,
            IndexingAgreementManagerAgreementNotAccepted(agreementId)
        );

        // If still active, route cancellation through the data service
        if (agreement.state == IRecurringCollector.AgreementState.Accepted) {
            address ds = info.dataService;
            require(ds.code.length != 0, IndexingAgreementManagerInvalidDataService(ds));
            ISubgraphService(ds).cancelIndexingAgreementByPayer(agreementId);
            emit AgreementCanceled(agreementId, info.indexer);
        }
        // else: already canceled (CanceledByPayer or CanceledByServiceProvider) — skip cancel call, just reconcile

        // Reconcile to update escrow requirements after cancellation
        _reconcileAgreement($, agreementId);
        _fundEscrow($, info.indexer);
    }

    /// @inheritdoc IIndexingAgreementManager
    function removeAgreement(bytes16 agreementId) external {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.exists, IndexingAgreementManagerAgreementNotOffered(agreementId));

        // Re-read from RecurringCollector to get current state
        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);

        // Calculate current max next claim - must be 0 to remove
        uint256 currentMaxClaim;
        if (agreement.state == IRecurringCollector.AgreementState.NotAccepted) {
            // Not yet accepted — removable only if offer deadline has passed
            // solhint-disable-next-line gas-strict-inequalities
            if (block.timestamp <= info.deadline) {
                currentMaxClaim = info.maxNextClaim;
            }
            // else: deadline passed, currentMaxClaim stays 0 (expired offer)
        } else {
            currentMaxClaim = RECURRING_COLLECTOR.getMaxNextClaim(agreementId);
        }
        require(currentMaxClaim == 0, IndexingAgreementManagerAgreementStillClaimable(agreementId, currentMaxClaim));

        address indexer = info.indexer;
        uint256 totalToRemove = info.maxNextClaim + info.pendingUpdateMaxNextClaim;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Clean up storage
        $.requiredEscrow[indexer] -= totalToRemove;
        $.indexerAgreementIds[indexer].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit AgreementRemoved(agreementId, indexer);
    }

    /// @inheritdoc IIndexingAgreementManager
    function reconcileAgreement(bytes16 agreementId) external {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.exists, IndexingAgreementManagerAgreementNotOffered(agreementId));

        _reconcileAgreement($, agreementId);
        _fundEscrow($, info.indexer);
    }

    /// @inheritdoc IIndexingAgreementManager
    function reconcile(address indexer) external {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage agreementIds = $.indexerAgreementIds[indexer];
        uint256 count = agreementIds.length();

        for (uint256 i = 0; i < count; ++i) {
            bytes16 agreementId = bytes16(agreementIds.at(i));
            _reconcileAgreement($, agreementId);
        }

        _fundEscrow($, indexer);
    }

    /// @inheritdoc IIndexingAgreementManager
    function reconcileBatch(bytes16[] calldata agreementIds) external {
        IndexingAgreementManagerStorage storage $ = _getStorage();

        // Phase 1: reconcile all agreements
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            if (!$.agreements[agreementIds[i]].exists) continue;
            _reconcileAgreement($, agreementIds[i]);
        }

        // Phase 2: fund escrow per unique indexer.
        // The lastFunded check is a gas optimization that skips consecutive duplicates.
        // Non-consecutive duplicates may call _fundEscrow twice for the same indexer,
        // which is idempotent (the second call finds no deficit) — just extra gas.
        // Callers can sort agreementIds by indexer to maximize dedup benefit.
        address lastFunded;
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            address idx = $.agreements[agreementIds[i]].indexer;
            if (idx == address(0) || idx == lastFunded) continue;
            _fundEscrow($, idx);
            lastFunded = idx;
        }
    }

    /// @inheritdoc IIndexingAgreementManager
    function maintain(address indexer) external {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        require($.indexerAgreementIds[indexer].length() == 0, IndexingAgreementManagerStillHasAgreements(indexer));

        // If a previous thaw has been initiated, try to complete withdrawal
        if ($.thawing[indexer]) {
            // solhint-disable-next-line no-empty-blocks
            try PAYMENTS_ESCROW.withdraw(address(RECURRING_COLLECTOR), indexer) {
                $.thawing[indexer] = false;
                emit EscrowWithdrawn(indexer);
            } catch {
                // Thaw not yet complete, nothing more to do
                return;
            }
        }

        // Thaw any remaining available balance
        uint256 available = PAYMENTS_ESCROW.getBalance(address(this), address(RECURRING_COLLECTOR), indexer);
        if (0 < available) {
            PAYMENTS_ESCROW.thaw(address(RECURRING_COLLECTOR), indexer, available);
            $.thawing[indexer] = true;
            emit EscrowThawed(indexer, available);
        }
    }

    // -- IIndexingAgreementManager: View Functions --

    /// @inheritdoc IIndexingAgreementManager
    function getRequiredEscrow(address indexer) external view returns (uint256) {
        return _getStorage().requiredEscrow[indexer];
    }

    /// @inheritdoc IIndexingAgreementManager
    function getDeficit(address indexer) external view returns (uint256) {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        uint256 required = $.requiredEscrow[indexer];
        uint256 currentBalance = PAYMENTS_ESCROW.getBalance(address(this), address(RECURRING_COLLECTOR), indexer);
        if (currentBalance < required) {
            return required - currentBalance;
        }
        return 0;
    }

    /// @inheritdoc IIndexingAgreementManager
    function getAgreementMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getStorage().agreements[agreementId].maxNextClaim;
    }

    /// @inheritdoc IIndexingAgreementManager
    function getAgreementInfo(bytes16 agreementId) external view returns (AgreementInfo memory) {
        return _getStorage().agreements[agreementId];
    }

    /// @inheritdoc IIndexingAgreementManager
    function getIndexerAgreementCount(address indexer) external view returns (uint256) {
        return _getStorage().indexerAgreementIds[indexer].length();
    }

    /// @inheritdoc IIndexingAgreementManager
    function getIndexerAgreements(address indexer) external view returns (bytes16[] memory) {
        IndexingAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage ids = $.indexerAgreementIds[indexer];
        uint256 count = ids.length();
        bytes16[] memory result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) {
            result[i] = bytes16(ids.at(i));
        }
        return result;
    }

    // -- Internal Functions --

    /**
     * @notice Reconcile a single agreement's max next claim against on-chain state
     * @param agreementId The agreement ID to reconcile
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAgreement(IndexingAgreementManagerStorage storage $, bytes16 agreementId) private {
        AgreementInfo storage info = $.agreements[agreementId];
        if (!info.exists) return;

        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);

        // If not yet accepted in RC, keep the pre-offer estimate
        if (agreement.state == IRecurringCollector.AgreementState.NotAccepted) {
            return;
        }

        // Clear pending update if it has been applied (updateNonce advanced past pending)
        // solhint-disable-next-line gas-strict-inequalities
        if (info.pendingUpdateHash != bytes32(0) && info.pendingUpdateNonce <= agreement.updateNonce) {
            $.requiredEscrow[info.indexer] -= info.pendingUpdateMaxNextClaim;
            delete $.authorizedHashes[info.pendingUpdateHash];
            info.pendingUpdateMaxNextClaim = 0;
            info.pendingUpdateNonce = 0;
            info.pendingUpdateHash = bytes32(0);
        }

        uint256 oldMaxClaim = info.maxNextClaim;
        uint256 newMaxClaim = RECURRING_COLLECTOR.getMaxNextClaim(agreementId);

        if (oldMaxClaim != newMaxClaim) {
            info.maxNextClaim = newMaxClaim;
            $.requiredEscrow[info.indexer] = $.requiredEscrow[info.indexer] - oldMaxClaim + newMaxClaim;
            emit AgreementReconciled(agreementId, oldMaxClaim, newMaxClaim);
        }
    }

    /**
     * @notice Fund the escrow for an indexer if there is a deficit
     * @dev Uses per-call approve (not infinite allowance). Safe because PaymentsEscrow
     * is a trusted protocol contract that transfers exactly the approved amount.
     * @param indexer The indexer to fund escrow for
     */
    // solhint-disable-next-line use-natspec
    function _fundEscrow(IndexingAgreementManagerStorage storage $, address indexer) private {
        uint256 currentBalance = PAYMENTS_ESCROW.getBalance(address(this), address(RECURRING_COLLECTOR), indexer);
        uint256 required = $.requiredEscrow[indexer];

        if (currentBalance < required) {
            uint256 deficit = required - currentBalance;
            uint256 available = GRAPH_TOKEN.balanceOf(address(this));
            uint256 toDeposit = deficit < available ? deficit : available;
            if (0 < toDeposit) {
                GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), toDeposit);
                PAYMENTS_ESCROW.deposit(address(RECURRING_COLLECTOR), indexer, toDeposit);
                emit EscrowFunded(indexer, required, currentBalance + toDeposit, toDeposit);
            }
        }
    }

    /**
     * @notice Get the ERC-7201 namespaced storage
     */
    // solhint-disable-next-line use-natspec
    function _getStorage() private pure returns (IndexingAgreementManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := INDEXING_AGREEMENT_MANAGER_STORAGE_LOCATION
        }
    }
}
