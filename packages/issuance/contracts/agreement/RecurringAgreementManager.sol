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
 * @notice Manages escrow for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator (implements IIssuanceTarget)
 * 2. Authorizes RCA acceptance via contract callback (implements IAgreementOwner)
 * 3. Tracks max-next-claim per agreement, deposits into PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, collector, provider) covers all managed
 * RCAs for that (collector, provider) pair. Each agreement stores its own collector
 * address. Other participants can independently use RCAs via the standard ECDSA-signed flow.
 *
 * @custom:security CEI — All external calls target trusted protocol contracts (PaymentsEscrow,
 * GRT, RecurringCollector) except {cancelAgreement}'s call to the data service, which is
 * governance-gated, and {_ensureIncomingDistributionToCurrentBlock}'s call to the issuance
 * allocator, which is also governance-gated. {nonReentrant} on {beforeCollection},
 * {afterCollection}, and {cancelAgreement} guards against reentrancy through these external
 * calls as defence-in-depth.
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

    /// @custom:storage-location erc7201:graphprotocol.issuance.storage.RecurringAgreementManager
    // solhint-disable-next-line gas-struct-packing
    struct RecurringAgreementManagerStorage {
        /// @notice Authorized agreement hashes — maps hash to agreementId (bytes16(0) = not authorized)
        mapping(bytes32 agreementHash => bytes16) authorizedHashes;
        /// @notice Per-agreement tracking data
        mapping(bytes16 agreementId => AgreementInfo) agreements;
        /// @notice Sum of maxNextClaim for all agreements per (collector, provider) pair
        mapping(address collector => mapping(address provider => uint256)) sumMaxNextClaim;
        /// @notice Set of agreement IDs per service provider (stored as bytes32 for EnumerableSet)
        mapping(address provider => EnumerableSet.Bytes32Set) providerAgreementIds;
        /// @notice Sum of sumMaxNextClaim across all (collector, provider) pairs
        uint256 sumMaxNextClaimAll;
        /// @notice Total unfunded escrow: sum of max(0, sumMaxNextClaim[c][p] - escrowSnap[c][p])
        uint256 totalEscrowDeficit;
        /// @notice Total number of tracked agreements across all providers
        uint256 totalAgreementCount;
        /// @notice Last known escrow balance per (collector, provider) pair (for snapshot diff)
        mapping(address collector => mapping(address provider => uint256)) escrowSnap;
        /// @notice Set of all collector addresses with active agreements
        EnumerableSet.AddressSet collectors;
        /// @notice Set of provider addresses per collector
        mapping(address collector => EnumerableSet.AddressSet) collectorProviders;
        /// @notice Number of agreements per (collector, provider) pair
        mapping(address collector => mapping(address provider => uint256)) pairAgreementCount;
        /// @notice The issuance allocator that mints GRT to this contract (20 bytes)
        /// @dev Packed slot (32/32 bytes): issuanceAllocator (20) + ensuredIncomingDistributedToBlock (8) +
        /// escrowBasis (1) + minOnDemandBasisThreshold (1) + minFullBasisMargin (1) + minThawFraction (1).
        /// All read together in _updateEscrow / beforeCollection.
        IIssuanceAllocationDistribution issuanceAllocator;
        /// @notice Block number when _ensureIncomingDistributionToCurrentBlock last ran
        uint64 ensuredIncomingDistributedToBlock;
        /// @notice Governance-configured escrow level (maximum target)
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
    function approveAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        bytes16 agreementId = $.authorizedHashes[agreementHash];

        if (agreementId == bytes16(0) || $.agreements[agreementId].provider == address(0)) return bytes4(0);

        return IAgreementOwner.approveAgreement.selector;
    }

    /// @inheritdoc IAgreementOwner
    function beforeCollection(bytes16 agreementId, uint256 tokensToCollect) external override nonReentrant {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        address provider = agreement.provider;
        if (provider == address(0)) return;
        _requireCollector(agreement);

        // JIT top-up: deposit only when escrow balance cannot cover this collection
        uint256 escrowBalance = _fetchEscrowAccount(msg.sender, provider).balance;
        if (tokensToCollect <= escrowBalance) return;

        // Ensure issuance is distributed so balanceOf reflects all available tokens
        _ensureIncomingDistributionToCurrentBlock($);

        uint256 deficit = tokensToCollect - escrowBalance;
        if (deficit < GRAPH_TOKEN.balanceOf(address(this))) {
            GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deficit);
            PAYMENTS_ESCROW.deposit(msg.sender, provider, deficit);
        }
    }

    /// @inheritdoc IAgreementOwner
    function afterCollection(bytes16 agreementId, uint256 /* tokensCollected */) external override nonReentrant {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return;
        _requireCollector(agreement);

        _reconcileAndUpdateEscrow($, agreementId);
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
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external onlyRole(AGREEMENT_MANAGER_ROLE) whenNotPaused returns (bytes16 agreementId) {
        agreementId = rcau.agreementId;
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        require(agreement.provider != address(0), AgreementNotOffered(agreementId));

        // Reconcile against on-chain state before layering a new pending update,
        // so escrow accounting is current and we can validate the nonce.
        _reconcileAgreement($, agreementId);

        // Validate nonce: must be the next expected nonce on the collector
        IRecurringCollector.AgreementData memory rca = agreement.collector.getAgreement(agreementId);
        uint32 expectedNonce = rca.updateNonce + 1;
        require(rcau.nonce == expectedNonce, InvalidUpdateNonce(agreementId, expectedNonce, rcau.nonce));

        // Clean up old pending hash if replacing
        if (agreement.pendingUpdateHash != bytes32(0)) delete $.authorizedHashes[agreement.pendingUpdateHash];

        // Authorize the RCAU hash for the IAgreementOwner callback
        bytes32 updateHash = agreement.collector.hashRCAU(rcau);
        $.authorizedHashes[updateHash] = agreementId;
        agreement.pendingUpdateNonce = rcau.nonce;
        agreement.pendingUpdateHash = updateHash;

        uint256 pendingMaxNextClaim = _computeMaxFirstClaim(
            rcau.maxOngoingTokensPerSecond,
            rcau.maxSecondsPerCollection,
            rcau.maxInitialTokens
        );
        _setAgreementMaxNextClaim($, agreementId, pendingMaxNextClaim, true);
        _updateEscrow($, address(agreement.collector), agreement.provider);

        emit AgreementUpdateOffered(agreementId, pendingMaxNextClaim, rcau.nonce);
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
    function revokeAgreementUpdate(
        bytes16 agreementId
    ) external onlyRole(AGREEMENT_MANAGER_ROLE) whenNotPaused returns (bool revoked) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        require(agreement.provider != address(0), AgreementNotOffered(agreementId));

        // Reconcile first — the update may have been accepted since the offer was made
        _reconcileAgreement($, agreementId);

        if (agreement.pendingUpdateHash == bytes32(0)) return false;

        uint256 pendingMaxClaim = agreement.pendingUpdateMaxNextClaim;
        uint32 nonce = agreement.pendingUpdateNonce;

        _setAgreementMaxNextClaim($, agreementId, 0, true);
        delete $.authorizedHashes[agreement.pendingUpdateHash];
        agreement.pendingUpdateNonce = 0;
        agreement.pendingUpdateHash = bytes32(0);

        _updateEscrow($, address(agreement.collector), agreement.provider);

        emit AgreementUpdateRevoked(agreementId, pendingMaxClaim, nonce);
        return true;
    }

    /// @inheritdoc IRecurringAgreementManagement
    function revokeOffer(
        bytes16 agreementId
    ) external onlyRole(AGREEMENT_MANAGER_ROLE) whenNotPaused returns (bool gone) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return true;

        // Only revoke un-accepted agreements — accepted ones must be canceled via cancelAgreement
        IRecurringCollector.AgreementData memory rca = agreement.collector.getAgreement(agreementId);
        require(rca.state == IRecurringCollector.AgreementState.NotAccepted, AgreementAlreadyAccepted(agreementId));

        address provider = _deleteAgreement($, agreementId, agreement);
        emit OfferRevoked(agreementId, provider);
        return true;
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
    function reconcileAgreement(bytes16 agreementId) external returns (bool exists) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return false;

        return !_reconcileAndCleanup($, agreementId, agreement);
    }

    /// @inheritdoc IRecurringAgreementManagement
    function reconcileCollectorProvider(address collector, address provider) external returns (bool exists) {
        return !_reconcilePairTracking(_getStorage(), collector, provider);
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

    // -- Internal Functions --

    /**
     * @notice Require that msg.sender is the agreement's collector.
     * @param agreement The agreement info to check against
     */
    function _requireCollector(AgreementInfo storage agreement) private view {
        require(msg.sender == address(agreement.collector), OnlyAgreementCollector());
    }

    /**
     * @notice Create agreement storage, authorize its hash, update pair tracking, and set max-next-claim.
     * @param agreementId The generated agreement ID
     * @param rca The recurring collection agreement parameters
     * @param collector The collector contract
     * @param agreementHash The hash of the RCA to authorize
     * @return maxNextClaim The computed max-next-claim for the new agreement
     */
    // solhint-disable-next-line use-natspec
    function _createAgreement(
        RecurringAgreementManagerStorage storage $,
        bytes16 agreementId,
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        IRecurringCollector collector,
        bytes32 agreementHash
    ) private returns (uint256 maxNextClaim) {
        $.authorizedHashes[agreementHash] = agreementId;

        $.agreements[agreementId] = AgreementInfo({
            provider: rca.serviceProvider,
            deadline: rca.deadline,
            pendingUpdateNonce: 0,
            maxNextClaim: 0,
            pendingUpdateMaxNextClaim: 0,
            agreementHash: agreementHash,
            pendingUpdateHash: bytes32(0),
            dataService: IDataServiceAgreements(rca.dataService),
            collector: collector
        });
        $.providerAgreementIds[rca.serviceProvider].add(bytes32(agreementId));
        ++$.totalAgreementCount;
        if (++$.pairAgreementCount[address(collector)][rca.serviceProvider] == 1) {
            $.collectorProviders[address(collector)].add(rca.serviceProvider);
            $.collectors.add(address(collector));
        }

        maxNextClaim = _computeMaxFirstClaim(
            rca.maxOngoingTokensPerSecond,
            rca.maxSecondsPerCollection,
            rca.maxInitialTokens
        );
        _setAgreementMaxNextClaim($, agreementId, maxNextClaim, false);
    }

    /**
     * @notice Compute maximum first claim from agreement rate parameters.
     * @param maxOngoingTokensPerSecond Maximum ongoing tokens per second
     * @param maxSecondsPerCollection Maximum seconds per collection period
     * @param maxInitialTokens Maximum initial tokens
     * @return Maximum possible claim amount
     */
    function _computeMaxFirstClaim(
        uint256 maxOngoingTokensPerSecond,
        uint256 maxSecondsPerCollection,
        uint256 maxInitialTokens
    ) private pure returns (uint256) {
        return maxOngoingTokensPerSecond * maxSecondsPerCollection + maxInitialTokens;
    }

    /**
     * @notice Reconcile an agreement and update escrow for its (collector, provider) pair.
     * @param agreementId The agreement ID to reconcile
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAndUpdateEscrow(RecurringAgreementManagerStorage storage $, bytes16 agreementId) private {
        _reconcileAgreement($, agreementId);
        AgreementInfo storage info = $.agreements[agreementId];
        _updateEscrow($, address(info.collector), info.provider);
    }

    /**
     * @notice Reconcile an agreement, update escrow, and delete if nothing left to claim.
     * @param agreementId The agreement ID to reconcile
     * @param agreement Storage pointer to the agreement info
     * @return deleted True if the agreement was removed
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAndCleanup(
        RecurringAgreementManagerStorage storage $,
        bytes16 agreementId,
        AgreementInfo storage agreement
    ) private returns (bool deleted) {
        _reconcileAndUpdateEscrow($, agreementId);
        if (agreement.maxNextClaim == 0) {
            address provider = _deleteAgreement($, agreementId, agreement);
            emit AgreementRemoved(agreementId, provider);
            return true;
        }
    }

    /**
     * @notice Reconcile a single agreement's max next claim against on-chain state
     * @param agreementId The agreement ID to reconcile
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAgreement(RecurringAgreementManagerStorage storage $, bytes16 agreementId) private {
        AgreementInfo storage agreement = $.agreements[agreementId];

        IRecurringCollector rc = agreement.collector;
        IRecurringCollector.AgreementData memory rca = rc.getAgreement(agreementId);

        // Not yet accepted — keep the pre-offer estimate unless the deadline has passed
        if (rca.state == IRecurringCollector.AgreementState.NotAccepted) {
            if (block.timestamp <= agreement.deadline) return;
            // Deadline passed: zero out so the caller can delete the expired offer
            uint256 prev = agreement.maxNextClaim;
            if (prev != 0) {
                _setAgreementMaxNextClaim($, agreementId, 0, false);
                emit AgreementReconciled(agreementId, prev, 0);
            }
            return;
        }

        // Clear pending update if applied (updateNonce advanced) or unreachable (agreement canceled)
        if (
            agreement.pendingUpdateHash != bytes32(0) &&
            (agreement.pendingUpdateNonce <= rca.updateNonce ||
                rca.state != IRecurringCollector.AgreementState.Accepted)
        ) {
            _setAgreementMaxNextClaim($, agreementId, 0, true);
            delete $.authorizedHashes[agreement.pendingUpdateHash];
            agreement.pendingUpdateNonce = 0;
            agreement.pendingUpdateHash = bytes32(0);
        }

        uint256 oldMaxClaim = agreement.maxNextClaim;
        uint256 newMaxClaim = rc.getMaxNextClaim(agreementId);

        if (oldMaxClaim != newMaxClaim) {
            _setAgreementMaxNextClaim($, agreementId, newMaxClaim, false);
            emit AgreementReconciled(agreementId, oldMaxClaim, newMaxClaim);
        }
    }

    /**
     * @notice Delete an agreement: clean up hashes, zero escrow obligations, remove from provider set, and update escrow.
     * @param agreementId The agreement ID to delete
     * @param agreement Storage pointer to the agreement info
     * @return provider The provider address (captured before deletion)
     */
    // solhint-disable-next-line use-natspec
    function _deleteAgreement(
        RecurringAgreementManagerStorage storage $,
        bytes16 agreementId,
        AgreementInfo storage agreement
    ) private returns (address provider) {
        provider = agreement.provider;
        IRecurringCollector collector = agreement.collector;

        // Clean up authorized hashes
        delete $.authorizedHashes[agreement.agreementHash];
        if (agreement.pendingUpdateHash != bytes32(0)) delete $.authorizedHashes[agreement.pendingUpdateHash];

        // Zero out escrow requirements before deleting
        _setAgreementMaxNextClaim($, agreementId, 0, false);
        _setAgreementMaxNextClaim($, agreementId, 0, true);
        --$.totalAgreementCount;
        $.providerAgreementIds[provider].remove(bytes32(agreementId));

        --$.pairAgreementCount[address(collector)][provider];
        delete $.agreements[agreementId];

        _reconcilePairTracking($, address(collector), provider);
    }

    /**
     * @notice Reconcile escrow then remove (collector, provider) tracking if fully drained.
     * @dev Calls {_updateEscrow} to withdraw completed thaws, then removes the pair from
     * tracking only when both pairAgreementCount and escrowSnap are zero.
     * Cascades to remove the collector when it has no remaining providers.
     * @return gone True if the pair is not tracked after this call
     */
    // solhint-disable-next-line use-natspec
    function _reconcilePairTracking(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private returns (bool gone) {
        _updateEscrow($, collector, provider);
        if ($.pairAgreementCount[collector][provider] != 0) return false;
        if ($.escrowSnap[collector][provider] != 0) return false;
        if ($.collectorProviders[collector].remove(provider)) {
            emit CollectorProviderRemoved(collector, provider);
            if ($.collectorProviders[collector].length() == 0) {
                $.collectors.remove(collector);
                emit CollectorRemoved(collector);
            }
        }
        return true;
    }

    /**
     * @notice Atomically set one escrow obligation slot of an agreement and cascade to provider/global totals.
     * @dev This and {_setEscrowSnap} are the only two functions that mutate totalEscrowDeficit.
     * @param agreementId The agreement to update
     * @param newValue The new obligation value
     * @param pending If true, updates pendingUpdateMaxNextClaim; otherwise updates maxNextClaim
     */
    // solhint-disable-next-line use-natspec
    function _setAgreementMaxNextClaim(
        RecurringAgreementManagerStorage storage $,
        bytes16 agreementId,
        uint256 newValue,
        bool pending
    ) private {
        AgreementInfo storage agreement = $.agreements[agreementId];

        uint256 oldValue = pending ? agreement.pendingUpdateMaxNextClaim : agreement.maxNextClaim;
        if (oldValue == newValue) return;

        address collector = address(agreement.collector);
        address provider = agreement.provider;
        uint256 oldDeficit = _providerEscrowDeficit($, collector, provider);

        if (pending) agreement.pendingUpdateMaxNextClaim = newValue;
        else agreement.maxNextClaim = newValue;

        $.sumMaxNextClaim[collector][provider] = $.sumMaxNextClaim[collector][provider] - oldValue + newValue;
        $.sumMaxNextClaimAll = $.sumMaxNextClaimAll - oldValue + newValue;
        $.totalEscrowDeficit = $.totalEscrowDeficit - oldDeficit + _providerEscrowDeficit($, collector, provider);
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
     * The effective basis is the configured escrowBasis limited based on spare balance
     * (balance - totalEscrowDeficit). OnDemand requires sumMaxNextClaimAll * threshold / 256 < spare.
     * Full requires sumMaxNextClaimAll * (256 + margin) / 256 < spare.
     *
     * @param collector The collector address
     * @param provider The service provider
     * @return min Deposit floor — deposit if balance is below this
     * @return max Thaw ceiling — thaw if balance is above this
     */
    // solhint-disable-next-line use-natspec
    function _escrowMinMax(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private view returns (uint256 min, uint256 max) {
        uint256 balance = GRAPH_TOKEN.balanceOf(address(this));
        uint256 totalDeficit = $.totalEscrowDeficit;
        uint256 spare = totalDeficit < balance ? balance - totalDeficit : 0;
        uint256 sumMaxNext = $.sumMaxNextClaimAll;

        EscrowBasis basis = $.escrowBasis;
        max = basis != EscrowBasis.JustInTime && ((sumMaxNext * uint256($.minOnDemandBasisThreshold)) / 256 < spare)
            ? $.sumMaxNextClaim[collector][provider]
            : 0;
        min = basis == EscrowBasis.Full && ((sumMaxNext * (256 + uint256($.minFullBasisMargin))) / 256 < spare)
            ? max
            : 0;
    }

    /**
     * @notice Compute a (collector, provider) pair's escrow deficit: max(0, sumMaxNext - snapshot).
     * @param collector The collector address
     * @param provider The service provider
     * @return deficit The amount not in escrow for this (collector, provider)
     */
    // solhint-disable-next-line use-natspec
    function _providerEscrowDeficit(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private view returns (uint256 deficit) {
        uint256 sumMaxNext = $.sumMaxNextClaim[collector][provider];
        uint256 snapshot = $.escrowSnap[collector][provider];

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
     * @param collector The collector contract address
     * @param provider The service provider to update escrow for
     */
    // solhint-disable-next-line use-natspec
    function _updateEscrow(RecurringAgreementManagerStorage storage $, address collector, address provider) private {
        _ensureIncomingDistributionToCurrentBlock($);

        // Sync snapshot before decisions: the escrow balance may have changed externally
        // (e.g. RecurringCollector.collect drained it before calling afterCollection).
        // Without this, totalEscrowDeficit is stale → spare is overstated → basis is inflated
        // → deposit attempt for tokens we don't have → revert swallowed by try/catch → snap
        // stays permanently stale.  Reading the fresh balance here makes the function
        // self-correcting regardless of prior callback failures.
        _setEscrowSnap($, collector, provider);

        IPaymentsEscrow.EscrowAccount memory account = _fetchEscrowAccount(collector, provider);
        (uint256 min, uint256 max) = _escrowMinMax($, collector, provider);

        // Defensive: PaymentsEscrow maintains tokensThawing <= balance, guard against external invariant breach
        uint256 escrowed = account.tokensThawing < account.balance ? account.balance - account.tokensThawing : 0;
        // Thaw threshold: ignore thaws below this for two reasons:
        // 1. Operational: small excess proportions are not worth thawing; better to wait for a larger rebalance.
        // 2. Anti-griefing: an attacker could deposit dust via depositTo(), trigger reconciliation,
        //    and start a tiny thaw that blocks legitimate thaw increases for the entire thawing period.
        uint256 thawThreshold = ($.sumMaxNextClaim[collector][provider] * uint256($.minThawFraction)) / 256;
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
        _setEscrowSnap($, collector, provider);
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
     * @param thawThreshold Thaw threshold — do not initiate a thaw if excess is less than this
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
    function _setEscrowSnap(RecurringAgreementManagerStorage storage $, address collector, address provider) private {
        uint256 oldEscrow = $.escrowSnap[collector][provider];
        uint256 newEscrow = _fetchEscrowAccount(collector, provider).balance;
        if (oldEscrow == newEscrow) return;

        uint256 oldDeficit = _providerEscrowDeficit($, collector, provider);
        $.escrowSnap[collector][provider] = newEscrow;
        uint256 newDeficit = _providerEscrowDeficit($, collector, provider);
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
     */
    // solhint-disable-next-line use-natspec
    function _ensureIncomingDistributionToCurrentBlock(RecurringAgreementManagerStorage storage $) private {
        // Uses low 8 bytes of block.number; consecutive blocks always differ so same-block
        // dedup works correctly even past uint64 wrap. A false match requires the previous
        // last call to have been exactly 2^64 blocks ago (~584 billion years at 1 block/s).
        uint64 blockNum;
        unchecked {
            blockNum = uint64(block.number);
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
