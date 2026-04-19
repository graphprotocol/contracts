// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

// solhint-disable gas-strict-inequalities

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IIssuanceAllocationDistribution } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceAllocationDistribution.sol";
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringEscrowManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringEscrowManagement.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IEmergencyRoleControl } from "@graphprotocol/interfaces/contracts/issuance/common/IEmergencyRoleControl.sol";

import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { IGraphToken } from "../common/IGraphToken.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/**
 * @title RecurringAgreementManager
 * @author Edge & Node
 * @notice Manages escrow for collector-managed agreements using issuance-allocated tokens.
 * This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator ({IIssuanceTarget})
 * 2. Offers and cancels agreements by calling collectors directly (AGREEMENT_MANAGER_ROLE-gated)
 * 3. Handles collection callbacks — JIT escrow top-up and post-collection reconciliation
 *    ({IAgreementOwner})
 * 4. Tracks max-next-claim per agreement, deposits into PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, collector, provider) covers all managed agreements for that
 * (collector, provider) pair. Agreements are namespaced under their collector to prevent
 * cross-collector ID collisions.
 *
 * @custom:design-coupling All collector interactions go through {IAgreementCollector}:
 * discovery via {IAgreementCollector.getAgreementDetails}, claim computation via
 * {IAgreementCollector.getMaxNextClaim}. A collector with a different pricing model or
 * agreement type works without changes here.
 *
 * @custom:security CEI — external calls target trusted protocol contracts (PaymentsEscrow,
 * GRT, issuance allocator) which are governance-gated.
 *
 * Collector trust: collectors are COLLECTOR_ROLE-gated (governor-managed). {offerAgreement}
 * and {cancelAgreement} call collectors directly. Discovery calls `getAgreementDetails`;
 * reconciliation calls `getMaxNextClaim` — these return values drive escrow accounting.
 * A broken or malicious collector can cause reconciliation to revert; use
 * {forceRemoveAgreement} as an operator escape hatch. Once tracked, reconciliation proceeds
 * even if COLLECTOR_ROLE is later revoked, ensuring orderly settlement.
 *
 * Collectors own agreement uniqueness, replay protection, and state transitions; this
 * contract does not re-check them.
 *
 * {offerAgreement} and {cancelAgreement} forward to the collector then reconcile locally.
 * The collector does not callback to `msg.sender`, so these methods own the full call
 * sequence and hold the reentrancy lock for the entire operation.
 *
 * All state-mutating entry points are {nonReentrant}.
 *
 * @custom:security-pause This contract and RecurringCollector are independently pausable.
 *
 * When paused, all permissionless state-changing operations are blocked: collection callbacks,
 * reconciliation, and agreement management. Operator-gated functions ({forceRemoveAgreement},
 * configuration setters) remain callable during pause.
 *
 * Cross-contract: when this contract is paused but RecurringCollector is not, providers can
 * still collect. The collector proceeds but payer callbacks revert (low-level calls, so
 * collection succeeds without JIT top-up). Escrow accounting drifts until unpaused and
 * {reconcileAgreement} is called. To fully halt collections, pause RecurringCollector too.
 *
 * Escalation ladder (targeted → full stop):
 * 1. {emergencyRevokeRole} — disable a specific actor (operator, collector, guardian)
 * 2. {emergencyClearEligibilityOracle} — fail-open if oracle blocks collections
 * 3. Pause this contract — stops all permissionless escrow management
 * 4. Pause RecurringCollector — stops all collections and state changes
 * 5. Pause both — full halt
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringAgreementManager is
    BaseUpgradeable,
    ReentrancyGuardTransient,
    IIssuanceTarget,
    IAgreementOwner,
    IRecurringAgreementManagement,
    IRecurringEscrowManagement,
    IProviderEligibilityManagement,
    IRecurringAgreements,
    IProviderEligibility,
    IEmergencyRoleControl
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Emitted when distributeIssuance() reverts (collection continues without fresh issuance)
    /// @param allocator The allocator that reverted
    event DistributeIssuanceFailed(address indexed allocator);

    /// @notice Thrown when the issuance allocator does not support IIssuanceAllocationDistribution
    error InvalidIssuanceAllocator(address allocator);

    /// @notice Thrown when attempting to emergency-revoke the governor role
    error CannotRevokeGovernorRole();

    // -- Role Constants --

    /**
     * @notice Role identifier for approved data service contracts
     * @dev Addresses with this role can be used as data services in offered agreements.
     * Admin: GOVERNOR_ROLE
     */
    bytes32 public constant DATA_SERVICE_ROLE = keccak256("DATA_SERVICE_ROLE");

    /**
     * @notice Role identifier for approved collector contracts
     * @dev Addresses with this role can be used as collectors in offered agreements.
     * Admin: GOVERNOR_ROLE
     */
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    /**
     * @notice Role identifier for agreement lifecycle operations
     * @dev Addresses with this role can offer, update, revoke, and cancel agreements.
     * Admin: OPERATOR_ROLE
     */
    bytes32 public constant AGREEMENT_MANAGER_ROLE = keccak256("AGREEMENT_MANAGER_ROLE");

    // -- Immutables --

    /// @notice The PaymentsEscrow contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPaymentsEscrow public immutable PAYMENTS_ESCROW;

    // -- Storage (ERC-7201) --

    /**
     * @notice Per-(collector, provider) pair tracking data
     * @param sumMaxNextClaim Sum of maxNextClaim for all agreements in this pair
     * @param escrowSnap Snapshot of escrow balance at the last _setEscrowSnap call.
     * Input to totalEscrowDeficit accounting, not a guarantee of the live balance — it can
     * drift between reconciliations (e.g. after beforeCollection's JIT deposit) until the
     * next _reconcileProviderEscrow resyncs it. Read the live balance via _fetchEscrowAccount
     * when actual solvency matters.
     * @param agreements Set of agreement IDs for this pair (stored as bytes32 for EnumerableSet)
     */
    struct CollectorProviderData {
        uint256 sumMaxNextClaim;
        uint256 escrowSnap;
        EnumerableSet.Bytes32Set agreements;
    }

    /**
     * @notice Per-collector tracking data
     * @param agreements Agreement data keyed by agreement ID
     * @param providers Per-provider tracking data
     * @param providerSet Set of provider addresses with active agreements
     */
    struct CollectorData {
        mapping(bytes16 agreementId => AgreementInfo) agreements;
        mapping(address provider => CollectorProviderData) providers;
        EnumerableSet.AddressSet providerSet;
    }

    /// @custom:storage-location erc7201:graphprotocol.issuance.storage.RecurringAgreementManager
    // solhint-disable-next-line gas-struct-packing
    struct RecurringAgreementManagerStorage {
        /// @notice Per-collector tracking data (agreements, providers, escrow)
        mapping(address collector => CollectorData) collectors;
        /// @notice Set of all collector addresses with active agreements
        EnumerableSet.AddressSet collectorSet;
        /// @notice Sum of sumMaxNextClaim across all (collector, provider) pairs
        uint256 sumMaxNextClaimAll;
        /// @notice Total unfunded escrow: sum of max(0, sumMaxNextClaim[c][p] - escrowSnap[c][p])
        uint256 totalEscrowDeficit;
        /// @notice The issuance allocator that mints GRT to this contract (20 bytes)
        /// @dev Packed slot (29/32 bytes): issuanceAllocator (20) + ensuredIncomingDistributedToBlock (4) +
        /// escrowBasis (1) + minOnDemandBasisThreshold (1) + minFullBasisMargin (1) + minThawFraction (1) +
        /// minResidualEscrowFactor (1).
        /// All read together in _reconcileProviderEscrow / beforeCollection.
        IIssuanceAllocationDistribution issuanceAllocator;
        /// @notice Block number when _ensureIncomingDistributionToCurrentBlock last ran
        uint32 ensuredIncomingDistributedToBlock;
        /// @notice Governance-configured escrow level (maximum aspiration)
        EscrowBasis escrowBasis;
        /// @notice Threshold for OnDemand: sumMaxNextClaimAll * threshold / 256 < spare.
        /// Governance-configured.
        uint8 minOnDemandBasisThreshold;
        /// @notice Margin for Full: sumMaxNextClaimAll * (256 + margin) / 256 < spare.
        /// Governance-configured.
        uint8 minFullBasisMargin;
        /// @notice Minimum thaw fraction: escrow excess below sumMaxNextClaim * minThawFraction / 256
        /// per (collector, provider) pair is skipped as operationally insignificant.
        /// Governance-configured.
        uint8 minThawFraction;
        /// @notice Minimum residual escrow factor: when a (collector, provider) pair has no agreements
        /// and the escrow balance is below 2^value, tracking is dropped; the residual is not worth
        /// the gas cost of further thaw/withdraw cycles. Funds remain in PaymentsEscrow but are no
        /// longer actively managed by RAM. 0 = drop only at zero balance. Governance-configured.
        /// Default 50 ≈ 0.001 GRT.
        uint8 minResidualEscrowFactor;
        /// @notice Optional oracle for checking payment eligibility of service providers (20/32 bytes in slot)
        IProviderEligibility providerEligibilityOracle;
    }

    // keccak256(abi.encode(uint256(keccak256("graphprotocol.issuance.storage.RecurringAgreementManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RECURRING_AGREEMENT_MANAGER_STORAGE_LOCATION =
        0x13814b254ec9c757012be47b3445539ef5e5e946eb9d2ef31ea6d4423bf88b00;

    // -- Constructor --

    /**
     * @notice Constructor for the RecurringAgreementManager contract
     * @param graphToken The Graph Token contract
     * @param paymentsEscrow The PaymentsEscrow contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(IGraphToken graphToken, IPaymentsEscrow paymentsEscrow) BaseUpgradeable(graphToken) {
        PAYMENTS_ESCROW = paymentsEscrow;
    }

    // -- Initialization --

    /**
     * @notice Initialize the RecurringAgreementManager contract
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);
        _setRoleAdmin(DATA_SERVICE_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(COLLECTOR_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(AGREEMENT_MANAGER_ROLE, OPERATOR_ROLE);

        RecurringAgreementManagerStorage storage $ = _getStorage();
        $.escrowBasis = EscrowBasis.Full;
        $.minOnDemandBasisThreshold = 128;
        $.minFullBasisMargin = 16;
        $.minThawFraction = 16;
        $.minResidualEscrowFactor = 50; // 2^50 ≈ 10^15 ≈ 0.001 GRT
    }

    // -- ERC165 --

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IIssuanceTarget).interfaceId ||
            interfaceId == type(IAgreementOwner).interfaceId ||
            interfaceId == type(IRecurringAgreementManagement).interfaceId ||
            interfaceId == type(IRecurringEscrowManagement).interfaceId ||
            interfaceId == type(IProviderEligibilityManagement).interfaceId ||
            interfaceId == type(IRecurringAgreements).interfaceId ||
            interfaceId == type(IProviderEligibility).interfaceId ||
            interfaceId == type(IEmergencyRoleControl).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- IIssuanceTarget --

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external virtual override {}

    /// @inheritdoc IIssuanceTarget
    /// @dev The allocator is expected to call distributeIssuance() (bringing distribution up to
    /// the current block) before any configuration change. As a result, the same-block dedup in
    /// {_ensureIncomingDistributionToCurrentBlock} is harmless: if a prior call already set the
    /// block marker, the allocator has already distributed. Governance should set the allocator
    /// in a standalone transaction to avoid interleaving with collection in the same block.
    /// Even if interleaved, the only effect is a one-block lag before the new allocator's
    /// distribution is picked up — corrected automatically on the next block.
    function setIssuanceAllocator(address newIssuanceAllocator) external virtual override onlyRole(GOVERNOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if (address($.issuanceAllocator) == newIssuanceAllocator) return;

        if (newIssuanceAllocator != address(0))
            require(
                ERC165Checker.supportsInterface(
                    newIssuanceAllocator,
                    type(IIssuanceAllocationDistribution).interfaceId
                ),
                InvalidIssuanceAllocator(newIssuanceAllocator)
            );

        emit IssuanceAllocatorSet(address($.issuanceAllocator), newIssuanceAllocator);
        $.issuanceAllocator = IIssuanceAllocationDistribution(newIssuanceAllocator);
    }

    // -- IAgreementOwner --

    /// @inheritdoc IAgreementOwner
    function beforeCollection(
        bytes16 agreementId,
        uint256 tokensToCollect
    ) external override whenNotPaused nonReentrant {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        address collector = msg.sender;
        address provider = _getAgreementProvider($, collector, agreementId);
        if (provider == address(0)) return;

        // JIT top-up: deposit only when escrow balance cannot cover this collection
        uint256 escrowBalance = _fetchEscrowAccount(collector, provider).balance;
        if (tokensToCollect <= escrowBalance) return;

        // Ensure issuance is distributed so balanceOf reflects all available tokens
        _ensureIncomingDistributionToCurrentBlock($);

        uint256 deficit = tokensToCollect - escrowBalance;
        if (deficit < GRAPH_TOKEN.balanceOf(address(this))) {
            GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deficit);
            PAYMENTS_ESCROW.deposit(collector, provider, deficit);
        }
    }

    /// @inheritdoc IAgreementOwner
    function afterCollection(
        bytes16 agreementId,
        uint256 /* tokensCollected */
    ) external override whenNotPaused nonReentrant {
        _reconcileAgreement(_getStorage(), msg.sender, agreementId);
    }

    // -- IRecurringAgreementManagement --

    /// @inheritdoc IRecurringAgreementManagement
    function offerAgreement(
        IAgreementCollector collector,
        uint8 offerType,
        bytes calldata offerData
    ) external onlyRole(AGREEMENT_MANAGER_ROLE) nonReentrant returns (bytes16 agreementId) {
        require(hasRole(COLLECTOR_ROLE, address(collector)), UnauthorizedCollector(address(collector)));

        // Forward to collector — no callback to msg.sender, we reconcile after return
        IAgreementCollector.AgreementDetails memory details = collector.offer(offerType, offerData, 0);
        require(hasRole(DATA_SERVICE_ROLE, details.dataService), UnauthorizedDataService(details.dataService));
        agreementId = details.agreementId;

        require(agreementId != bytes16(0), AgreementIdZero());
        require(details.payer == address(this), PayerMismatch(details.payer));
        require(details.serviceProvider != address(0), ServiceProviderZeroAddress());

        _reconcileAgreement(_getStorage(), address(collector), agreementId);
    }

    /// @inheritdoc IRecurringAgreementManagement
    function forceRemoveAgreement(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.collectors[address(collector)].agreements[agreementId];
        address provider = agreement.provider;
        if (provider == address(0)) return;

        CollectorProviderData storage cpd = $.collectors[address(collector)].providers[provider];

        _removeAgreement($, cpd, address(collector), provider, agreementId);
    }

    /// @inheritdoc IRecurringAgreementManagement
    /// @dev Emergency fail-open: if the oracle is broken or compromised and is wrongly
    /// blocking collections, the pause guardian can clear it so all providers become eligible.
    /// The governor can later set a replacement oracle.
    function emergencyClearEligibilityOracle() external override onlyRole(PAUSE_ROLE) {
        _setProviderEligibilityOracle(IProviderEligibility(address(0)));
    }

    /// @inheritdoc IEmergencyRoleControl
    /// @dev Governor role is excluded to prevent a pause guardian from locking out governance.
    function emergencyRevokeRole(bytes32 role, address account) external override onlyRole(PAUSE_ROLE) {
        require(role != GOVERNOR_ROLE, CannotRevokeGovernorRole());
        _revokeRole(role, account);
    }

    /// @inheritdoc IRecurringAgreementManagement
    function cancelAgreement(
        IAgreementCollector collector,
        bytes16 agreementId,
        bytes32 versionHash,
        uint16 options
    ) external onlyRole(AGREEMENT_MANAGER_ROLE) nonReentrant {
        // Forward to collector — no callback to msg.sender, we reconcile after return
        collector.cancel(agreementId, versionHash, options);
        _reconcileAgreement(_getStorage(), address(collector), agreementId);
    }

    /// @inheritdoc IRecurringAgreementManagement
    function reconcileAgreement(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external whenNotPaused nonReentrant returns (bool tracked) {
        tracked = _reconcileAgreement(_getStorage(), address(collector), agreementId);
    }

    /// @inheritdoc IRecurringAgreementManagement
    function reconcileProvider(
        IAgreementCollector collector,
        address provider
    ) external whenNotPaused nonReentrant returns (bool tracked) {
        return _reconcileProvider(_getStorage(), address(collector), provider);
    }

    // -- IRecurringEscrowManagement --

    /// @inheritdoc IRecurringEscrowManagement
    function setEscrowBasis(EscrowBasis basis) external onlyRole(OPERATOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.escrowBasis == basis) return;

        EscrowBasis oldBasis = $.escrowBasis;
        $.escrowBasis = basis;
        emit EscrowBasisSet(oldBasis, basis);
    }

    /// @inheritdoc IRecurringEscrowManagement
    function setMinOnDemandBasisThreshold(uint8 threshold) external onlyRole(OPERATOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.minOnDemandBasisThreshold == threshold) return;

        uint8 oldThreshold = $.minOnDemandBasisThreshold;
        $.minOnDemandBasisThreshold = threshold;
        emit MinOnDemandBasisThresholdSet(oldThreshold, threshold);
    }

    /// @inheritdoc IRecurringEscrowManagement
    function setMinFullBasisMargin(uint8 margin) external onlyRole(OPERATOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.minFullBasisMargin == margin) return;

        uint8 oldMargin = $.minFullBasisMargin;
        $.minFullBasisMargin = margin;
        emit MinFullBasisMarginSet(oldMargin, margin);
    }

    /// @inheritdoc IRecurringEscrowManagement
    function setMinThawFraction(uint8 fraction) external onlyRole(OPERATOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.minThawFraction == fraction) return;

        uint8 oldFraction = $.minThawFraction;
        $.minThawFraction = fraction;
        emit MinThawFractionSet(oldFraction, fraction);
    }

    /// @inheritdoc IRecurringEscrowManagement
    function setMinResidualEscrowFactor(uint8 value) external onlyRole(OPERATOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.minResidualEscrowFactor == value) return;

        uint8 oldValue = $.minResidualEscrowFactor;
        $.minResidualEscrowFactor = value;
        emit MinResidualEscrowFactorSet(oldValue, value);
    }

    // -- IProviderEligibilityManagement --

    /// @inheritdoc IProviderEligibilityManagement
    function setProviderEligibilityOracle(IProviderEligibility oracle) external onlyRole(GOVERNOR_ROLE) {
        _setProviderEligibilityOracle(oracle);
    }

    // solhint-disable-next-line use-natspec
    function _setProviderEligibilityOracle(IProviderEligibility oracle) private {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if (address($.providerEligibilityOracle) == address(oracle)) return;

        IProviderEligibility oldOracle = $.providerEligibilityOracle;
        $.providerEligibilityOracle = oracle;
        emit ProviderEligibilityOracleSet(oldOracle, oracle);
    }

    /// @inheritdoc IProviderEligibilityManagement
    function getProviderEligibilityOracle() external view returns (IProviderEligibility) {
        return _getStorage().providerEligibilityOracle;
    }

    // -- IProviderEligibility --

    /// @inheritdoc IProviderEligibility
    /// @dev When no oracle is configured (address(0)), all providers are eligible.
    /// When an oracle is set, delegates to the oracle's isEligible check.
    function isEligible(address serviceProvider) external view override returns (bool eligible) {
        IProviderEligibility oracle = _getStorage().providerEligibilityOracle;
        eligible = (address(oracle) == address(0)) || oracle.isEligible(serviceProvider);
    }

    // -- IRecurringAgreements --

    /// @inheritdoc IRecurringAgreements
    function getSumMaxNextClaim(IAgreementCollector collector, address provider) external view returns (uint256) {
        return _getStorage().collectors[address(collector)].providers[provider].sumMaxNextClaim;
    }

    /// @inheritdoc IRecurringAgreements
    function getEscrowAccount(
        IAgreementCollector collector,
        address provider
    ) external view returns (IPaymentsEscrow.EscrowAccount memory account) {
        return _fetchEscrowAccount(address(collector), provider);
    }

    /// @inheritdoc IRecurringAgreements
    function getAgreementMaxNextClaim(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external view returns (uint256) {
        return _getStorage().collectors[address(collector)].agreements[agreementId].maxNextClaim;
    }

    /// @inheritdoc IRecurringAgreements
    function getAgreementInfo(
        IAgreementCollector collector,
        bytes16 agreementId
    ) external view returns (AgreementInfo memory) {
        return _getStorage().collectors[address(collector)].agreements[agreementId];
    }

    /// @inheritdoc IRecurringAgreements
    function getAgreementCount(IAgreementCollector collector, address provider) external view returns (uint256) {
        return _getStorage().collectors[address(collector)].providers[provider].agreements.length();
    }

    /// @inheritdoc IRecurringAgreements
    function getAgreementAt(
        IAgreementCollector collector,
        address provider,
        uint256 index
    ) external view returns (bytes16) {
        return bytes16(_getStorage().collectors[address(collector)].providers[provider].agreements.at(index));
    }

    /// @inheritdoc IRecurringAgreements
    function getEscrowBasis() external view returns (EscrowBasis) {
        return _getStorage().escrowBasis;
    }

    /// @inheritdoc IRecurringAgreements
    function getSumMaxNextClaim() external view returns (uint256) {
        return _getStorage().sumMaxNextClaimAll;
    }

    /// @inheritdoc IRecurringAgreements
    function getTotalEscrowDeficit() external view returns (uint256) {
        return _getStorage().totalEscrowDeficit;
    }

    /// @inheritdoc IRecurringAgreements
    function getMinOnDemandBasisThreshold() external view returns (uint8) {
        return _getStorage().minOnDemandBasisThreshold;
    }

    /// @inheritdoc IRecurringAgreements
    function getMinFullBasisMargin() external view returns (uint8) {
        return _getStorage().minFullBasisMargin;
    }

    /// @inheritdoc IRecurringAgreements
    function getMinThawFraction() external view returns (uint8) {
        return _getStorage().minThawFraction;
    }

    /// @inheritdoc IRecurringAgreements
    function getMinResidualEscrowFactor() external view returns (uint8) {
        return _getStorage().minResidualEscrowFactor;
    }

    /// @inheritdoc IRecurringAgreements
    function getCollectorCount() external view returns (uint256) {
        return _getStorage().collectorSet.length();
    }

    /// @inheritdoc IRecurringAgreements
    function getCollectorAt(uint256 index) external view returns (IAgreementCollector) {
        return IAgreementCollector(_getStorage().collectorSet.at(index));
    }

    /// @inheritdoc IRecurringAgreements
    function getProviderCount(IAgreementCollector collector) external view returns (uint256) {
        return _getStorage().collectors[address(collector)].providerSet.length();
    }

    /// @inheritdoc IRecurringAgreements
    function getProviderAt(IAgreementCollector collector, uint256 index) external view returns (address) {
        return _getStorage().collectors[address(collector)].providerSet.at(index);
    }

    /// @inheritdoc IRecurringAgreements
    function getEscrowSnap(IAgreementCollector collector, address provider) external view returns (uint256) {
        return _getStorage().collectors[address(collector)].providers[provider].escrowSnap;
    }

    /**
     * @notice Get the service provider for an agreement, discovering from the collector if first-seen.
     * @dev Returns the cached provider for known agreements. For first-seen agreements:
     * reads from the collector, validates roles and payer, registers in tracking sets,
     * and returns the provider. Returns address(0) for agreements that don't belong to
     * this manager (unauthorized collector, wrong payer, unauthorized data service, or
     * non-existent). Once tracked, reconciliation bypasses this function's discovery path.
     * @param $ The storage reference
     * @param collector The collector contract address
     * @param agreementId The agreement ID
     * @return provider The service provider address, or address(0) if not ours
     */
    // solhint-disable-next-line use-natspec
    function _getAgreementProvider(
        RecurringAgreementManagerStorage storage $,
        address collector,
        bytes16 agreementId
    ) private returns (address provider) {
        provider = $.collectors[collector].agreements[agreementId].provider;
        if (provider != address(0)) return provider;

        // Untracked agreement; validate collector role, existence, payer, and data service.
        // COLLECTOR_ROLE is required for discovery (first encounter). Once tracked, reconciliation
        // of already-added agreements proceeds regardless of role — a deauthorized collector's
        // agreements can still be reconciled, settled, and force-removed.
        if (!hasRole(COLLECTOR_ROLE, collector)) {
            emit AgreementRejected(agreementId, collector, AgreementRejectionReason.UnauthorizedCollector);
            return address(0);
        }
        IAgreementCollector.AgreementDetails memory details = IAgreementCollector(collector).getAgreementDetails(
            agreementId,
            0
        );
        provider = details.serviceProvider;
        if (provider == address(0)) {
            emit AgreementRejected(agreementId, collector, AgreementRejectionReason.UnknownAgreement);
            return address(0);
        }
        if (details.payer != address(this)) {
            emit AgreementRejected(agreementId, collector, AgreementRejectionReason.PayerMismatch);
            return address(0);
        }
        if (!hasRole(DATA_SERVICE_ROLE, details.dataService)) {
            emit AgreementRejected(agreementId, collector, AgreementRejectionReason.UnauthorizedDataService);
            return address(0);
        }

        // Register agreement
        $.collectors[collector].agreements[agreementId].provider = provider;
        CollectorProviderData storage cpd = $.collectors[collector].providers[provider];
        cpd.agreements.add(bytes32(agreementId));
        $.collectors[collector].providerSet.add(provider);
        $.collectorSet.add(collector);
        emit AgreementAdded(agreementId, collector, details.dataService, provider);
    }

    /**
     * @notice Discover (if first-seen) and reconcile a single agreement.
     * @dev Used by {afterCollection}, {reconcileAgreement}, {offerAgreement}, and {cancelAgreement}.
     * Resolves the provider via {_getAgreementProvider}, refreshes the cached
     * maxNextClaim from the collector, and reconciles escrow.
     * @param $ The storage reference
     * @param collector The collector contract address
     * @param agreementId The agreement ID
     * @return tracked True if the agreement is still tracked after this call
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAgreement(
        RecurringAgreementManagerStorage storage $,
        address collector,
        bytes16 agreementId
    ) private returns (bool tracked) {
        address provider = _getAgreementProvider($, collector, agreementId);
        if (provider == address(0)) return false;

        AgreementInfo storage agreement = $.collectors[collector].agreements[agreementId];
        CollectorProviderData storage cpd = $.collectors[collector].providers[provider];

        // Refresh cached maxNextClaim from collector
        uint256 newMaxClaim = IAgreementCollector(collector).getMaxNextClaim(agreementId);

        // Update agreement + all derived totals (reads old value from storage)
        uint256 oldMaxClaim = _setAgreementMaxNextClaim($, cpd, agreement, newMaxClaim);
        if (oldMaxClaim != newMaxClaim) emit AgreementReconciled(agreementId, oldMaxClaim, newMaxClaim);

        tracked = newMaxClaim != 0;
        if (!tracked) _removeAgreement($, cpd, collector, provider, agreementId);
        else _reconcileProviderEscrow($, collector, provider);
    }

    /**
     * @notice Remove an agreement and reconcile the provider's escrow.
     * @dev Zeroes the agreement's maxNextClaim contribution before deleting, so callers
     * do not need to call {_setAgreementMaxNextClaim} themselves.
     * @param $ The storage reference
     * @param cpd The provider's CollectorProviderData
     * @param collector The collector contract address
     * @param provider Service provider address
     * @param agreementId The agreement ID
     */
    // solhint-disable-next-line use-natspec
    function _removeAgreement(
        RecurringAgreementManagerStorage storage $,
        CollectorProviderData storage cpd,
        address collector,
        address provider,
        bytes16 agreementId
    ) private {
        _setAgreementMaxNextClaim($, cpd, $.collectors[collector].agreements[agreementId], 0);
        cpd.agreements.remove(bytes32(agreementId));
        delete $.collectors[collector].agreements[agreementId];
        emit AgreementRemoved(agreementId);
        _reconcileProvider($, collector, provider);
    }

    /**
     * @notice Reconcile escrow then remove (collector, provider) tracking if below residual threshold.
     * @dev For tracked pairs (in providerSet): runs {_reconcileProviderEscrow}, then drops tracking
     * when no agreements remain and escrow balance is at or below the residual threshold.
     * For untracked pairs: performs a blind drain (withdraw matured thaw, thaw remainder) without
     * re-creating tracking state.
     *
     * The residual threshold = 2^minResidualEscrowFactor. Below this, the residual is not worth
     * the gas cost of further thaw/withdraw cycles, so tracking is dropped. Funds remain in
     * PaymentsEscrow, just no longer actively managed by RAM. A subsequent {_offerAgreement}
     * for the same pair will re-add tracking naturally.
     *
     * Cascades to remove the collector when it has no remaining providers.
     * @param $ The storage reference
     * @param collector The collector contract address
     * @param provider Service provider address
     * @return tracked True if the pair is still tracked after this call
     */
    // solhint-disable-next-line use-natspec
    function _reconcileProvider(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private returns (bool tracked) {
        if (!$.collectors[collector].providerSet.contains(provider)) {
            // Not tracked — blind drain without re-creating tracking state.
            _drainUntracked(collector, provider);
            return false;
        }

        _reconcileProviderEscrow($, collector, provider);
        CollectorProviderData storage cpd = $.collectors[collector].providers[provider];

        // Drop tracking when no agreements and escrow is below residual threshold.
        // Funds remain in PaymentsEscrow; deficit contribution is already 0 (sumMaxNextClaim == 0).
        // Read real balance (escrowSnap is already cleared when sumMaxNextClaim == 0).
        tracked =
            cpd.agreements.length() != 0 ||
            (2 ** uint256($.minResidualEscrowFactor) <= _fetchEscrowAccount(collector, provider).balance);
        if (!tracked && $.collectors[collector].providerSet.remove(provider)) {
            emit ProviderRemoved(collector, provider);
            if ($.collectors[collector].providerSet.length() == 0) {
                // Provider agreement count will already be zero at this point.
                $.collectorSet.remove(collector);
                emit CollectorRemoved(collector);
            }
        }
    }

    /**
     * @notice Blind drain for an untracked (collector, provider) escrow pair.
     * @dev Withdraws matured thaw if any, then starts a new thaw for remaining balance.
     * Does not read or write any RAM tracking state. Only acts when no thaw is active
     * (after withdraw or if none was started), so thaw() is safe — no timer to reset.
     * @param collector The collector contract address
     * @param provider Service provider address
     */
    function _drainUntracked(address collector, address provider) private {
        IPaymentsEscrow.EscrowAccount memory account = _fetchEscrowAccount(collector, provider);
        if (0 < account.tokensThawing && account.thawEndTimestamp < block.timestamp) {
            PAYMENTS_ESCROW.withdraw(collector, provider);
            account = _fetchEscrowAccount(collector, provider);
        }
        if (account.tokensThawing == 0 && 0 < account.balance)
            PAYMENTS_ESCROW.thaw(collector, provider, account.balance);
    }

    /**
     * @notice The sole mutation point for agreement.maxNextClaim and all derived totals.
     * @dev ALL writes to agreement.maxNextClaim, sumMaxNextClaim, sumMaxNextClaimAll, and
     * claim-driven totalEscrowDeficit MUST go through this function. It reads the old value
     * from storage itself — callers cannot supply a stale or incorrect old value.
     * (Escrow-balance-driven deficit updates go through {_setEscrowSnap} instead.)
     * @param $ The storage reference
     * @param cpd The collector-provider data storage pointer
     * @param agreement The agreement whose maxNextClaim is changing
     * @param newMaxClaim The new maxNextClaim for the agreement
     * @return oldMaxClaim The previous maxNextClaim (read from storage)
     */
    // solhint-disable-next-line use-natspec
    function _setAgreementMaxNextClaim(
        RecurringAgreementManagerStorage storage $,
        CollectorProviderData storage cpd,
        AgreementInfo storage agreement,
        uint256 newMaxClaim
    ) private returns (uint256 oldMaxClaim) {
        oldMaxClaim = agreement.maxNextClaim;

        if (oldMaxClaim != newMaxClaim) {
            agreement.maxNextClaim = newMaxClaim;

            uint256 oldDeficit = _providerEscrowDeficit(cpd);
            cpd.sumMaxNextClaim = cpd.sumMaxNextClaim - oldMaxClaim + newMaxClaim;
            $.sumMaxNextClaimAll = $.sumMaxNextClaimAll - oldMaxClaim + newMaxClaim;
            $.totalEscrowDeficit = $.totalEscrowDeficit - oldDeficit + _providerEscrowDeficit(cpd);
        }
    }

    /**
     * @notice Compute escrow levels (min, max) based on escrow basis.
     * @dev Escrow ladder:
     *
     * | Level      | min (deposit floor) | max (thaw ceiling) |
     * |------------|---------------------|--------------------|
     * | Full       | sumMaxNext          | sumMaxNext         |
     * | OnDemand   | 0                   | sumMaxNext         |
     * | JustInTime | 0                   | 0                  |
     *
     * The effective basis is the configured escrowBasis degraded based on spare balance
     * (balance - totalEscrowDeficit). OnDemand requires sumMaxNextClaimAll * threshold / 256 < spare.
     * Full requires sumMaxNextClaimAll * (256 + margin) / 256 < spare.
     *
     * @param $ The storage reference
     * @param sumMaxNextClaim The collector-provider's sumMaxNextClaim
     * @return min Deposit floor — deposit if balance is below this
     * @return max Thaw ceiling — thaw if balance is above this
     */
    // solhint-disable-next-line use-natspec
    function _escrowMinMax(
        RecurringAgreementManagerStorage storage $,
        uint256 sumMaxNextClaim
    ) private view returns (uint256 min, uint256 max) {
        uint256 balance = GRAPH_TOKEN.balanceOf(address(this));
        uint256 totalDeficit = $.totalEscrowDeficit;
        uint256 spare = totalDeficit < balance ? balance - totalDeficit : 0;
        uint256 sumMaxNext = $.sumMaxNextClaimAll;

        EscrowBasis basis = $.escrowBasis;
        max = basis != EscrowBasis.JustInTime && ((sumMaxNext * uint256($.minOnDemandBasisThreshold)) / 256 < spare)
            ? sumMaxNextClaim
            : 0;
        min = basis == EscrowBasis.Full && ((sumMaxNext * (256 + uint256($.minFullBasisMargin))) / 256 < spare)
            ? max
            : 0;
    }

    /**
     * @notice Compute a (collector, provider) pair's escrow deficit: max(0, sumMaxNext - snapshot).
     * @param cpd The collector-provider data
     * @return deficit The amount not in escrow for this (collector, provider)
     */
    // solhint-disable-next-line use-natspec
    function _providerEscrowDeficit(CollectorProviderData storage cpd) private view returns (uint256 deficit) {
        uint256 sumMaxNext = cpd.sumMaxNextClaim;
        uint256 snapshot = cpd.escrowSnap;

        deficit = (snapshot < sumMaxNext) ? sumMaxNext - snapshot : 0;
    }

    /**
     * @notice Update escrow state for a (collector, provider) pair: adjust thaw targets,
     * withdraw completed thaws, thaw excess, or deposit deficit.
     * @dev Sequential state normalization using (min, max) from {_escrowMinMax}:
     * - min: deposit floor — deposit if effective balance (balance - tokensThawing) is below this
     * - max: thaw ceiling — thaw effective balance above this, unless it would reset the thaw timer
     *
     * Steps:
     * 1. Adjust thaw target — cancel/reduce unrealised thawing to keep min <= effective balance,
     *    or increase thawing to bring effective balance toward max (without resetting timer).
     * 2. Withdraw completed thaw — realised thawing is always withdrawn, even if within [min, max].
     * 3. Thaw excess — if no thaw is active (possibly after a withdraw), start a new thaw for
     *    any balance above max.
     * 4. Deposit deficit — if no thaw is active, deposit to reach min.
     *
     * Steps 3 and 4 are mutually exclusive (min <= max). Only one runs per call.
     * The thaw timer is never reset: step 1 passes evenIfTimerReset=false, and steps 3/4
     * only run when tokensThawing == 0.
     *
     * Uses per-call approve (not infinite allowance). Safe because PaymentsEscrow
     * is a trusted protocol contract that transfers exactly the approved amount.
     *
     * Updates escrow snapshot at the end for global tracking.
     *
     * @param $ The storage reference
     * @param collector The collector contract address
     * @param provider The service provider to update escrow for
     */
    // solhint-disable-next-line use-natspec
    function _reconcileProviderEscrow(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private {
        _ensureIncomingDistributionToCurrentBlock($);

        CollectorProviderData storage cpd = $.collectors[collector].providers[provider];
        // Sync snapshot before decisions: the escrow balance may have changed externally.
        // Without this, totalEscrowDeficit is stale → spare is overstated → basis is inflated
        // → deposit attempt for tokens we don't have → revert swallowed → snap
        // stays permanently stale.  Reading the fresh balance here makes the function
        // self-correcting regardless of prior callback failures.
        _setEscrowSnap($, cpd, collector, provider);

        IPaymentsEscrow.EscrowAccount memory account = _fetchEscrowAccount(collector, provider);
        (uint256 min, uint256 max) = _escrowMinMax($, cpd.sumMaxNextClaim);

        // Defensive: PaymentsEscrow maintains tokensThawing <= balance, guard against external invariant breach
        uint256 escrowed = account.tokensThawing < account.balance ? account.balance - account.tokensThawing : 0;
        // Thaw threshold: ignore thaws below this to prevent micro-thaw griefing.
        // An attacker depositing dust via depositTo() then triggering reconciliation could start
        // a tiny thaw that blocks legitimate thaw increases for the entire thawing period.
        uint256 thawThreshold = (cpd.sumMaxNextClaim * uint256($.minThawFraction)) / 256;

        // Objectives in order of priority:
        // We want to end with escrowed of at least min, and seek to thaw down to no more than max.
        // 1. Do not reset thaw timer if a thaw is in progress.
        //    (This is to avoid thrash of restarting thaws resulting in never withdrawing excess.)
        // 2. Make minimal adjustment to thawing tokens to get as close to min/max as possible.
        //    (First cancel unrealised thawing before depositing.)
        // 3. Skip thaw if excess above max is below the minimum thaw threshold.
        uint256 excess = max < escrowed ? escrowed - max : 0;
        uint256 thawTarget = (escrowed < min)
            ? (min < account.balance ? account.balance - min : 0)
            : (max < account.balance ? account.balance - max : 0);
        // Act when the target differs, but skip thaw increases below thawThreshold (obj 3).
        // Deficit adjustments (escrowed < min) always proceed — the threshold only gates new thaws.
        if (thawTarget != account.tokensThawing && (escrowed < min || thawThreshold <= excess)) {
            PAYMENTS_ESCROW.adjustThaw(collector, provider, thawTarget, false);
            account = _fetchEscrowAccount(collector, provider);
        }

        _withdrawAndRebalance(collector, provider, account, min, max, thawThreshold);
        _setEscrowSnap($, cpd, collector, provider);
    }

    /**
     * @notice Withdraw completed thaws and rebalance: thaw excess above max or deposit deficit below min.
     * @dev Realised thawing is always withdrawn, even if within [min, max].
     * Then if no thaw is active: thaw any balance above max, or deposit to reach min.
     * These last two steps are mutually exclusive (min <= max). Only one runs per call.
     * @param collector The collector contract address
     * @param provider Service provider address
     * @param account Current escrow account state
     * @param min Deposit floor
     * @param max Thaw ceiling
     * @param thawThreshold Minimum excess to start a new thaw
     */
    function _withdrawAndRebalance(
        address collector,
        address provider,
        IPaymentsEscrow.EscrowAccount memory account,
        uint256 min,
        uint256 max,
        uint256 thawThreshold
    ) private {
        // Withdraw any remaining thawed tokens (realised thawing is withdrawn even if within [min, max])
        if (0 < account.tokensThawing && account.thawEndTimestamp < block.timestamp) {
            uint256 withdrawn = account.tokensThawing < account.balance ? account.tokensThawing : account.balance;
            PAYMENTS_ESCROW.withdraw(collector, provider);
            emit EscrowWithdrawn(provider, collector, withdrawn);
            account = _fetchEscrowAccount(collector, provider);
        }

        if (account.tokensThawing == 0) {
            if (max < account.balance) {
                uint256 excess = account.balance - max;
                if (thawThreshold <= excess)
                    // Thaw excess above max (might have withdrawn allowing a new thaw to start)
                    PAYMENTS_ESCROW.adjustThaw(collector, provider, excess, false);
            } else if (account.balance < min) {
                // Deposit any deficit below min (deposit exactly the missing amount, no more)
                uint256 deficit = min - account.balance;
                GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deficit);
                PAYMENTS_ESCROW.deposit(collector, provider, deficit);
                emit EscrowFunded(provider, collector, deficit);
            }
        }
    }

    /**
     * @notice Atomically sync the escrow snapshot for a (collector, provider) pair after escrow mutations.
     * @dev This and {_setAgreementMaxNextClaim} are the only two functions that mutate totalEscrowDeficit.
     * @param collector The collector address
     * @param provider The service provider
     */
    // solhint-disable-next-line use-natspec
    function _setEscrowSnap(
        RecurringAgreementManagerStorage storage $,
        CollectorProviderData storage cpd,
        address collector,
        address provider
    ) private {
        uint256 oldEscrow = cpd.escrowSnap;
        // No need to track escrow when no claims remain (deficit is 0 regardless).
        uint256 newEscrow = cpd.sumMaxNextClaim != 0 ? _fetchEscrowAccount(collector, provider).balance : 0;
        if (oldEscrow == newEscrow) return;

        uint256 oldDeficit = _providerEscrowDeficit(cpd);
        cpd.escrowSnap = newEscrow;
        uint256 newDeficit = _providerEscrowDeficit(cpd);
        $.totalEscrowDeficit = $.totalEscrowDeficit - oldDeficit + newDeficit;
    }

    // solhint-disable-next-line use-natspec
    function _fetchEscrowAccount(
        address collector,
        address provider
    ) private view returns (IPaymentsEscrow.EscrowAccount memory account) {
        (account.balance, account.tokensThawing, account.thawEndTimestamp) = PAYMENTS_ESCROW.escrowAccounts(
            address(this),
            collector,
            provider
        );
    }

    /**
     * @notice Trigger issuance distribution so that balanceOf(this) reflects all available tokens.
     * @dev No-op if allocator is not set or already ensured this block. The local ensuredIncomingDistributedToBlock
     * check avoids the external call overhead (~2800 gas) on redundant same-block invocations
     * (e.g. beforeCollection + afterCollection in the same collection tx).
     * @param $ The storage reference
     */
    // solhint-disable-next-line use-natspec
    function _ensureIncomingDistributionToCurrentBlock(RecurringAgreementManagerStorage storage $) private {
        // Uses low 4 bytes of block.number; consecutive blocks always differ so same-block
        // dedup works correctly even past uint32 wrap. A false match requires the previous
        // last call to have been exactly 2^32 blocks ago (~1,630 years at 12 s/block).
        uint32 blockNum;
        unchecked {
            blockNum = uint32(block.number);
        }
        if ($.ensuredIncomingDistributedToBlock == blockNum) return;
        $.ensuredIncomingDistributedToBlock = blockNum;

        IIssuanceAllocationDistribution allocator = $.issuanceAllocator;
        if (address(allocator) == address(0)) return;

        try allocator.distributeIssuance() {} catch {
            emit DistributeIssuanceFailed(address(allocator));
        }
    }

    /**
     * @notice Get the ERC-7201 namespaced storage
     */
    // solhint-disable-next-line use-natspec
    function _getStorage() private pure returns (RecurringAgreementManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := RECURRING_AGREEMENT_MANAGER_STORAGE_LOCATION
        }
    }
}
