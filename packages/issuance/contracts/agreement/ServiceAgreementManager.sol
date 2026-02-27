// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IServiceAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IServiceAgreementManager.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";

import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title ServiceAgreementManager
 * @author Edge & Node
 * @notice Manages escrow funding for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator (implements IIssuanceTarget)
 * 2. Authorizes RCA acceptance via contract callback (implements IContractApprover)
 * 3. Tracks max-next-claim per agreement, funds PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, RecurringCollector, provider) covers all managed
 * RCAs for that service provider. Other participants can independently use RCAs via the
 * standard ECDSA-signed flow.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract ServiceAgreementManager is BaseUpgradeable, IIssuanceTarget, IContractApprover, IServiceAgreementManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // -- Immutables --

    /// @notice The PaymentsEscrow contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPaymentsEscrow public immutable PAYMENTS_ESCROW;

    /// @notice The RecurringCollector contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRecurringCollector public immutable RECURRING_COLLECTOR;

    // -- Storage (ERC-7201) --

    /// @custom:storage-location erc7201:graphprotocol.issuance.storage.ServiceAgreementManager
    struct ServiceAgreementManagerStorage {
        /// @notice Authorized agreement hashes — maps hash to agreementId (bytes16(0) = not authorized)
        mapping(bytes32 agreementHash => bytes16) authorizedHashes;
        /// @notice Per-agreement tracking data
        mapping(bytes16 agreementId => AgreementInfo) agreements;
        /// @notice Sum of maxNextClaim for all agreements per service provider
        mapping(address provider => uint256) requiredEscrow;
        /// @notice Set of agreement IDs per service provider (stored as bytes32 for EnumerableSet)
        mapping(address provider => EnumerableSet.Bytes32Set) providerAgreementIds;
    }

    // solhint-disable-next-line gas-named-return-values
    // keccak256(abi.encode(uint256(keccak256("graphprotocol.issuance.storage.ServiceAgreementManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SERVICE_AGREEMENT_MANAGER_STORAGE_LOCATION =
        0xa9c66ea3fa38aa138f879d9aaa0c12f2c90b6da6c040ce09545560b725e41b00;

    // -- Constructor --

    /**
     * @notice Constructor for the ServiceAgreementManager contract
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
     * @notice Initialize the ServiceAgreementManager contract
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
            interfaceId == type(IServiceAgreementManager).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- IIssuanceTarget --

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external virtual override {
        emit IIssuanceTarget.BeforeIssuanceAllocationChange();
    }

    /// @inheritdoc IIssuanceTarget
    /// @dev No-op: ServiceAgreementManager receives tokens via transfer, does not need the allocator address.
    function setIssuanceAllocator(address /* issuanceAllocator */) external virtual override onlyRole(GOVERNOR_ROLE) {}

    // -- IContractApprover --

    /// @inheritdoc IContractApprover
    function approveAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        bytes16 agreementId = $.authorizedHashes[agreementHash];

        if (agreementId == bytes16(0) || $.agreements[agreementId].provider == address(0)) return bytes4(0);

        return IContractApprover.approveAgreement.selector;
    }

    // -- IServiceAgreementManager: Core Functions --

    /// @inheritdoc IServiceAgreementManager
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        require(rca.payer == address(this), PayerMustBeManager(rca.payer, address(this)));
        require(rca.serviceProvider != address(0), ServiceProviderZeroAddress());
        require(rca.dataService != address(0), DataServiceZeroAddress());

        ServiceAgreementManagerStorage storage $ = _getStorage();

        agreementId = RECURRING_COLLECTOR.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );

        require($.agreements[agreementId].provider == address(0), AgreementAlreadyOffered(agreementId));

        // Calculate max next claim from RCA parameters (pre-acceptance, so use initial + ongoing)
        uint256 maxNextClaim = rca.maxOngoingTokensPerSecond * rca.maxSecondsPerCollection + rca.maxInitialTokens;

        // Authorize the agreement hash for the IContractApprover callback
        bytes32 agreementHash = RECURRING_COLLECTOR.hashRCA(rca);
        $.authorizedHashes[agreementHash] = agreementId;

        // Store agreement tracking data
        $.agreements[agreementId] = AgreementInfo({
            provider: rca.serviceProvider,
            deadline: rca.deadline,
            dataService: rca.dataService,
            pendingUpdateNonce: 0,
            maxNextClaim: maxNextClaim,
            pendingUpdateMaxNextClaim: 0,
            agreementHash: agreementHash,
            pendingUpdateHash: bytes32(0)
        });
        $.providerAgreementIds[rca.serviceProvider].add(bytes32(agreementId));
        $.requiredEscrow[rca.serviceProvider] += maxNextClaim;

        // Update escrow: fund deficit (partial-cancel thaw if needed), thaw excess
        _updateEscrow($, rca.serviceProvider);

        emit AgreementOffered(agreementId, rca.serviceProvider, maxNextClaim);
    }

    /// @inheritdoc IServiceAgreementManager
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        agreementId = rcau.agreementId;
        ServiceAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        require(agreement.provider != address(0), AgreementNotOffered(agreementId));

        // Calculate pending max next claim from RCAU parameters (conservative: includes initial + ongoing)
        uint256 pendingMaxNextClaim = rcau.maxOngoingTokensPerSecond * rcau.maxSecondsPerCollection +
            rcau.maxInitialTokens;

        // If replacing an existing pending update, remove old pending from requiredEscrow and clean up hash
        if (agreement.pendingUpdateHash != bytes32(0)) {
            $.requiredEscrow[agreement.provider] -= agreement.pendingUpdateMaxNextClaim;
            delete $.authorizedHashes[agreement.pendingUpdateHash];
        }

        // Authorize the RCAU hash for the IContractApprover callback
        bytes32 updateHash = RECURRING_COLLECTOR.hashRCAU(rcau);
        $.authorizedHashes[updateHash] = agreementId;

        // Store pending update tracking
        agreement.pendingUpdateMaxNextClaim = pendingMaxNextClaim;
        agreement.pendingUpdateNonce = rcau.nonce;
        agreement.pendingUpdateHash = updateHash;
        $.requiredEscrow[agreement.provider] += pendingMaxNextClaim;

        // Update escrow: fund deficit (partial-cancel thaw if needed), thaw excess
        _updateEscrow($, agreement.provider);

        emit AgreementUpdateOffered(agreementId, pendingMaxNextClaim, rcau.nonce);
    }

    /// @inheritdoc IServiceAgreementManager
    function revokeOffer(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        // Only revoke un-accepted agreements — accepted ones must be canceled via cancelAgreement
        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);
        require(
            agreement.state == IRecurringCollector.AgreementState.NotAccepted,
            AgreementAlreadyAccepted(agreementId)
        );

        address provider = info.provider;
        uint256 totalToRemove = info.maxNextClaim + info.pendingUpdateMaxNextClaim;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Clean up storage
        $.requiredEscrow[provider] -= totalToRemove;
        $.providerAgreementIds[provider].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit OfferRevoked(agreementId, provider);
        _updateEscrow($, provider);
    }

    /// @inheritdoc IServiceAgreementManager
    function cancelAgreement(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);

        // Not accepted — use revokeOffer instead
        require(agreement.state != IRecurringCollector.AgreementState.NotAccepted, AgreementNotAccepted(agreementId));

        // If still active, route cancellation through the data service
        if (agreement.state == IRecurringCollector.AgreementState.Accepted) {
            address ds = info.dataService;
            require(ds.code.length != 0, InvalidDataService(ds));
            IDataServiceAgreements(ds).cancelIndexingAgreementByPayer(agreementId);
            emit AgreementCanceled(agreementId, info.provider);
        }
        // else: already canceled (CanceledByPayer or CanceledByServiceProvider) — skip cancel call, just reconcile

        // Reconcile to update escrow requirements after cancellation
        _reconcileAgreement($, agreementId);
        _updateEscrow($, info.provider);
    }

    /// @inheritdoc IServiceAgreementManager
    function removeAgreement(bytes16 agreementId) external {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

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
        require(currentMaxClaim == 0, AgreementStillClaimable(agreementId, currentMaxClaim));

        address provider = info.provider;
        uint256 totalToRemove = info.maxNextClaim + info.pendingUpdateMaxNextClaim;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Clean up storage
        $.requiredEscrow[provider] -= totalToRemove;
        $.providerAgreementIds[provider].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit AgreementRemoved(agreementId, provider);
        _updateEscrow($, provider);
    }

    /// @inheritdoc IServiceAgreementManager
    function reconcileAgreement(bytes16 agreementId) external {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        _reconcileAgreement($, agreementId);
        _updateEscrow($, info.provider);
    }

    /// @inheritdoc IServiceAgreementManager
    function reconcile(address provider) external {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage agreementIds = $.providerAgreementIds[provider];
        uint256 count = agreementIds.length();

        for (uint256 i = 0; i < count; ++i) {
            bytes16 agreementId = bytes16(agreementIds.at(i));
            _reconcileAgreement($, agreementId);
        }

        _updateEscrow($, provider);
    }

    /// @inheritdoc IServiceAgreementManager
    function reconcileBatch(bytes16[] calldata agreementIds) external {
        ServiceAgreementManagerStorage storage $ = _getStorage();

        // Phase 1: reconcile all agreements
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            if ($.agreements[agreementIds[i]].provider == address(0)) continue;
            _reconcileAgreement($, agreementIds[i]);
        }

        // Phase 2: update escrow per unique service provider.
        // The lastUpdated check is a gas optimization that skips consecutive duplicates.
        // Non-consecutive duplicates may call _updateEscrow twice for the same service provider,
        // which is idempotent (the second call finds no change) — just extra gas.
        // Callers can sort agreementIds by service provider to maximize dedup benefit.
        address lastUpdated;
        for (uint256 i = 0; i < agreementIds.length; ++i) {
            address sp = $.agreements[agreementIds[i]].provider;
            if (sp == address(0) || sp == lastUpdated) continue;
            _updateEscrow($, sp);
            lastUpdated = sp;
        }
    }

    /// @inheritdoc IServiceAgreementManager
    function updateEscrow(address provider) external {
        _updateEscrow(_getStorage(), provider);
    }

    // -- IServiceAgreementManager: View Functions --

    /// @inheritdoc IServiceAgreementManager
    function getRequiredEscrow(address provider) external view returns (uint256) {
        return _getStorage().requiredEscrow[provider];
    }

    /// @inheritdoc IServiceAgreementManager
    function getDeficit(address provider) external view returns (uint256) {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        uint256 required = $.requiredEscrow[provider];
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.getEscrowAccount(
            address(this),
            address(RECURRING_COLLECTOR),
            provider
        );
        uint256 currentBalance = account.balance - account.tokensThawing;
        if (currentBalance < required) {
            return required - currentBalance;
        }
        return 0;
    }

    /// @inheritdoc IServiceAgreementManager
    function getAgreementMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getStorage().agreements[agreementId].maxNextClaim;
    }

    /// @inheritdoc IServiceAgreementManager
    function getAgreementInfo(bytes16 agreementId) external view returns (AgreementInfo memory) {
        return _getStorage().agreements[agreementId];
    }

    /// @inheritdoc IServiceAgreementManager
    function getProviderAgreementCount(address provider) external view returns (uint256) {
        return _getStorage().providerAgreementIds[provider].length();
    }

    /// @inheritdoc IServiceAgreementManager
    function getProviderAgreements(address provider) external view returns (bytes16[] memory) {
        ServiceAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage ids = $.providerAgreementIds[provider];
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
    function _reconcileAgreement(ServiceAgreementManagerStorage storage $, bytes16 agreementId) private {
        AgreementInfo storage info = $.agreements[agreementId];

        IRecurringCollector.AgreementData memory agreement = RECURRING_COLLECTOR.getAgreement(agreementId);

        // If not yet accepted in RC, keep the pre-offer estimate
        if (agreement.state == IRecurringCollector.AgreementState.NotAccepted) {
            return;
        }

        // Clear pending update if it has been applied (updateNonce advanced past pending)
        // solhint-disable-next-line gas-strict-inequalities
        if (info.pendingUpdateHash != bytes32(0) && info.pendingUpdateNonce <= agreement.updateNonce) {
            $.requiredEscrow[info.provider] -= info.pendingUpdateMaxNextClaim;
            delete $.authorizedHashes[info.pendingUpdateHash];
            info.pendingUpdateMaxNextClaim = 0;
            info.pendingUpdateNonce = 0;
            info.pendingUpdateHash = bytes32(0);
        }

        uint256 oldMaxClaim = info.maxNextClaim;
        uint256 newMaxClaim = RECURRING_COLLECTOR.getMaxNextClaim(agreementId);

        if (oldMaxClaim != newMaxClaim) {
            info.maxNextClaim = newMaxClaim;
            $.requiredEscrow[info.provider] = $.requiredEscrow[info.provider] - oldMaxClaim + newMaxClaim;
            emit AgreementReconciled(agreementId, oldMaxClaim, newMaxClaim);
        }
    }

    /**
     * @notice Update escrow state for a service provider: withdraw completed thaws, fund any deficit,
     * and thaw excess balance.
     * @dev Sequential state normalization:
     * 1. Withdraw completed thaw (skip when escrow is short — cancelThaw avoids round-trip)
     * 2. Reduce thaw if effective balance (balance - thawing) is short
     * 3. Not thawing: start thaw for excess or deposit for deficit
     *
     * Uses per-call approve (not infinite allowance). Safe because PaymentsEscrow
     * is a trusted protocol contract that transfers exactly the approved amount.
     *
     * @param provider The service provider to update escrow for
     */
    // solhint-disable-next-line use-natspec
    function _updateEscrow(ServiceAgreementManagerStorage storage $, address provider) private {
        address collector = address(RECURRING_COLLECTOR);
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.getEscrowAccount(
            address(this),
            collector,
            provider
        );
        uint256 required = $.requiredEscrow[provider];

        // Withdraw completed thaw (skip when escrow is short — step 2 cancels thaw instead)
        bool thawReady = 0 < account.thawEndTimestamp && account.thawEndTimestamp < block.timestamp;
        if (thawReady && required < account.balance) {
            uint256 withdrawn = PAYMENTS_ESCROW.withdraw(collector, provider);
            emit EscrowWithdrawn(provider, collector, withdrawn);
            account = PAYMENTS_ESCROW.getEscrowAccount(address(this), collector, provider);
        }

        // Reduce thaw if effective balance is short; else thawing at acceptable level
        if (0 < account.tokensThawing)
            if (account.balance - account.tokensThawing < required) {
                uint256 target = account.balance < required ? 0 : account.balance - required;
                PAYMENTS_ESCROW.thaw(collector, provider, target, false);
                // solhint-disable-next-line gas-strict-inequalities
                if (required <= account.balance) return;
                // thaw cancelled; fall through to deposit below
            } else return;

        // Not thawing: thaw excess or deposit deficit
        if (required < account.balance) {
            uint256 excess = account.balance - required;
            PAYMENTS_ESCROW.thaw(collector, provider, excess, false);
        } else if (account.balance < required) {
            uint256 deficit = required - account.balance;
            uint256 available = GRAPH_TOKEN.balanceOf(address(this));
            uint256 toDeposit = deficit < available ? deficit : available;
            if (0 < toDeposit) {
                GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), toDeposit);
                PAYMENTS_ESCROW.deposit(collector, provider, toDeposit);
                emit EscrowFunded(provider, collector, toDeposit);
            }
        }
    }

    /**
     * @notice Get the ERC-7201 namespaced storage
     */
    // solhint-disable-next-line use-natspec
    function _getStorage() private pure returns (ServiceAgreementManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := SERVICE_AGREEMENT_MANAGER_STORAGE_LOCATION
        }
    }
}
