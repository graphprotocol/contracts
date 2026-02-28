// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.27;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IContractApprover } from "@graphprotocol/interfaces/contracts/horizon/IContractApprover.sol";
import { IRecurringAgreementManager } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManager.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";
import { IRewardsEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IRewardsEligibility.sol";

import { BaseUpgradeable } from "../common/BaseUpgradeable.sol";
import { IGraphToken } from "../common/IGraphToken.sol";

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title RecurringAgreementManager
 * @author Edge & Node
 * @notice Manages escrow for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator (implements IIssuanceTarget)
 * 2. Authorizes RCA acceptance via contract callback (implements IContractApprover)
 * 3. Tracks max-next-claim per agreement, deposits into PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, collector, provider) covers all managed
 * RCAs for that (collector, provider) pair. Each agreement stores its own collector
 * address. Other participants can independently use RCAs via the standard ECDSA-signed flow.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringAgreementManager is
    BaseUpgradeable,
    IIssuanceTarget,
    IContractApprover,
    IRecurringAgreementManager,
    IRewardsEligibility
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

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

    // -- Immutables --

    /// @notice The PaymentsEscrow contract
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IPaymentsEscrow public immutable PAYMENTS_ESCROW;

    // -- Storage (ERC-7201) --

    /// @custom:storage-location erc7201:graphprotocol.issuance.storage.RecurringAgreementManager
    struct RecurringAgreementManagerStorage {
        /// @notice Authorized agreement hashes — maps hash to agreementId (bytes16(0) = not authorized)
        mapping(bytes32 agreementHash => bytes16) authorizedHashes;
        /// @notice Per-agreement tracking data
        mapping(bytes16 agreementId => AgreementInfo) agreements;
        /// @notice Sum of maxNextClaim for all agreements per (collector, provider) pair
        mapping(address collector => mapping(address provider => uint256)) sumMaxNextClaim;
        /// @notice Set of agreement IDs per service provider (stored as bytes32 for EnumerableSet)
        mapping(address provider => EnumerableSet.Bytes32Set) providerAgreementIds;
        /// @notice Governance-configured escrow level (not modified by enforced JIT)
        EscrowBasis escrowBasis;
        /// @notice Sum of sumMaxNextClaim across all (collector, provider) pairs
        uint256 sumMaxNextClaimAll;
        /// @notice Total unfunded escrow: sum of max(0, sumMaxNextClaim[c][p] - escrowSnap[c][p])
        uint256 totalEscrowDeficit;
        /// @notice Total number of tracked agreements across all providers
        uint256 totalAgreementCount;
        /// @notice Last known escrow balance per (collector, provider) pair (for snapshot diff)
        mapping(address collector => mapping(address provider => uint256)) escrowSnap;
        /// @notice Whether JIT mode is enforced (beforeCollection couldn't deposit)
        bool enforcedJit;
        /// @notice Optional oracle for checking payment eligibility of service providers
        IRewardsEligibility paymentEligibilityOracle;
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
        _getStorage().escrowBasis = EscrowBasis.Full;
    }

    // -- ERC165 --

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IIssuanceTarget).interfaceId ||
            interfaceId == type(IContractApprover).interfaceId ||
            interfaceId == type(IRecurringAgreementManager).interfaceId ||
            interfaceId == type(IRewardsEligibility).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // -- IIssuanceTarget --

    /// @inheritdoc IIssuanceTarget
    function beforeIssuanceAllocationChange() external virtual override {}

    /// @inheritdoc IIssuanceTarget
    /// @dev No-op: RecurringAgreementManager receives tokens via transfer, does not need the allocator address.
    function setIssuanceAllocator(address /* issuanceAllocator */) external virtual override onlyRole(GOVERNOR_ROLE) {}

    // -- IContractApprover --

    /// @inheritdoc IContractApprover
    function approveAgreement(bytes32 agreementHash) external view override returns (bytes4) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        bytes16 agreementId = $.authorizedHashes[agreementHash];

        if (agreementId == bytes16(0) || $.agreements[agreementId].provider == address(0)) return bytes4(0);

        return IContractApprover.approveAgreement.selector;
    }

    /// @inheritdoc IContractApprover
    function beforeCollection(bytes16 agreementId, uint256 tokensToCollect) external override {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        address provider = agreement.provider;
        if (provider == address(0)) return;
        _requireCollector(agreement);

        // Only deposit if escrow is short for this collection
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.escrowAccounts(
            address(this),
            msg.sender,
            provider
        );
        if (tokensToCollect < account.balance) return;

        uint256 deficit = tokensToCollect - account.balance;
        if (deficit < GRAPH_TOKEN.balanceOf(address(this))) {
            GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deficit);
            PAYMENTS_ESCROW.deposit(msg.sender, provider, deficit);
        } else if (!$.enforcedJit) {
            $.enforcedJit = true;
            emit EnforcedJit($.escrowBasis);
        }
    }

    /// @inheritdoc IContractApprover
    function afterCollection(bytes16 agreementId, uint256 /* tokensCollected */) external override {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return;
        _requireCollector(agreement);

        _reconcileAndUpdateEscrow($, agreementId);
    }

    // -- IRecurringAgreementManager: Core Functions --

    /// @inheritdoc IRecurringAgreementManager
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        IRecurringCollector collector
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        require(rca.payer == address(this), PayerMustBeManager(rca.payer, address(this)));
        require(rca.serviceProvider != address(0), ServiceProviderZeroAddress());
        require(hasRole(DATA_SERVICE_ROLE, rca.dataService), UnauthorizedDataService(rca.dataService));
        require(hasRole(COLLECTOR_ROLE, address(collector)), UnauthorizedCollector(address(collector)));

        RecurringAgreementManagerStorage storage $ = _getStorage();

        agreementId = collector.generateAgreementId(
            rca.payer,
            rca.dataService,
            rca.serviceProvider,
            rca.deadline,
            rca.nonce
        );
        require($.agreements[agreementId].provider == address(0), AgreementAlreadyOffered(agreementId));

        // Authorize the agreement hash for the IContractApprover callback
        bytes32 agreementHash = collector.hashRCA(rca);
        $.authorizedHashes[agreementHash] = agreementId;

        // Store agreement tracking data (maxNextClaim set to 0; _setAgreementMaxNextClaim handles accounting)
        $.agreements[agreementId] = AgreementInfo({
            provider: rca.serviceProvider,
            deadline: rca.deadline,
            dataService: IDataServiceAgreements(rca.dataService),
            pendingUpdateNonce: 0,
            maxNextClaim: 0,
            pendingUpdateMaxNextClaim: 0,
            agreementHash: agreementHash,
            pendingUpdateHash: bytes32(0),
            collector: collector
        });
        $.providerAgreementIds[rca.serviceProvider].add(bytes32(agreementId));
        ++$.totalAgreementCount;

        uint256 maxNextClaim = _computeMaxFirstClaim(
            rca.maxOngoingTokensPerSecond,
            rca.maxSecondsPerCollection,
            rca.maxInitialTokens
        );
        _setAgreementMaxNextClaim($, agreementId, maxNextClaim, false);
        _updateEscrow($, collector, rca.serviceProvider);

        emit AgreementOffered(agreementId, rca.serviceProvider, maxNextClaim);
    }

    /// @inheritdoc IRecurringAgreementManager
    function offerAgreementUpdate(
        IRecurringCollector.RecurringCollectionAgreementUpdate calldata rcau
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        agreementId = rcau.agreementId;
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        require(agreement.provider != address(0), AgreementNotOffered(agreementId));

        // Clean up old pending hash if replacing
        if (agreement.pendingUpdateHash != bytes32(0)) delete $.authorizedHashes[agreement.pendingUpdateHash];

        // Authorize the RCAU hash for the IContractApprover callback
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
        _updateEscrow($, agreement.collector, agreement.provider);

        emit AgreementUpdateOffered(agreementId, pendingMaxNextClaim, rcau.nonce);
    }

    /// @inheritdoc IRecurringAgreementManager
    function revokeOffer(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        require(agreement.provider != address(0), AgreementNotOffered(agreementId));

        // Only revoke un-accepted agreements — accepted ones must be canceled via cancelAgreement
        IRecurringCollector.AgreementData memory rca = agreement.collector.getAgreement(agreementId);
        require(rca.state == IRecurringCollector.AgreementState.NotAccepted, AgreementAlreadyAccepted(agreementId));

        address provider = _deleteAgreement($, agreementId, agreement);
        emit OfferRevoked(agreementId, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function cancelAgreement(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return;

        IRecurringCollector.AgreementData memory rca = agreement.collector.getAgreement(agreementId);

        // Not accepted — use revokeOffer instead
        require(rca.state != IRecurringCollector.AgreementState.NotAccepted, AgreementNotAccepted(agreementId));

        // If still active, route cancellation through the data service
        if (rca.state == IRecurringCollector.AgreementState.Accepted) {
            IDataServiceAgreements ds = agreement.dataService;
            require(address(ds).code.length != 0, InvalidDataService(address(ds)));
            ds.cancelIndexingAgreementByPayer(agreementId);
            emit AgreementCanceled(agreementId, agreement.provider);
        }
        // else: already canceled (CanceledByPayer or CanceledByServiceProvider) — skip cancel call, just reconcile

        _reconcileAndUpdateEscrow($, agreementId);
    }

    /// @inheritdoc IRecurringAgreementManager
    function removeAgreement(bytes16 agreementId) external {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return;

        // Re-read from the agreement's collector to get current state
        IRecurringCollector.AgreementData memory rca = agreement.collector.getAgreement(agreementId);

        // Calculate current max next claim - must be 0 to remove
        uint256 currentMaxClaim;
        if (rca.state == IRecurringCollector.AgreementState.NotAccepted) {
            // Not yet accepted — removable only if offer deadline has passed
            // solhint-disable-next-line gas-strict-inequalities
            if (block.timestamp <= agreement.deadline) currentMaxClaim = agreement.maxNextClaim;
            // else: deadline passed, currentMaxClaim stays 0 (expired offer)
        } else currentMaxClaim = agreement.collector.getMaxNextClaim(agreementId);

        require(currentMaxClaim == 0, AgreementStillClaimable(agreementId, currentMaxClaim));

        address provider = _deleteAgreement($, agreementId, agreement);
        emit AgreementRemoved(agreementId, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function reconcileAgreement(bytes16 agreementId) external {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage agreement = $.agreements[agreementId];
        if (agreement.provider == address(0)) return;

        _reconcileAndUpdateEscrow($, agreementId);
    }

    /// @inheritdoc IRecurringAgreementManager
    function updateEscrow(IRecurringCollector collector, address provider) external {
        _updateEscrow(_getStorage(), collector, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function setEscrowBasis(EscrowBasis basis) external onlyRole(GOVERNOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if ($.escrowBasis == basis) return;
        EscrowBasis oldBasis = $.escrowBasis;
        $.escrowBasis = basis;
        emit EscrowBasisChanged(oldBasis, basis);
    }

    /// @inheritdoc IRecurringAgreementManager
    function setPaymentEligibilityOracle(IRewardsEligibility oracle) external onlyRole(GOVERNOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        if (address($.paymentEligibilityOracle) == address(oracle)) return;
        IRewardsEligibility oldOracle = $.paymentEligibilityOracle;
        $.paymentEligibilityOracle = oracle;
        emit PaymentEligibilityOracleSet(oldOracle, oracle);
    }

    // -- IRewardsEligibility --

    /// @inheritdoc IRewardsEligibility
    /// @dev When no oracle is configured (address(0)), all providers are eligible.
    /// When an oracle is set, delegates to the oracle's isEligible check.
    function isEligible(address serviceProvider) external view override returns (bool eligible) {
        IRewardsEligibility oracle = _getStorage().paymentEligibilityOracle;
        eligible = (address(oracle) == address(0)) || oracle.isEligible(serviceProvider);
    }

    // -- IRecurringAgreementManager: View Functions --

    /// @inheritdoc IRecurringAgreementManager
    function sumMaxNextClaim(IRecurringCollector collector, address provider) external view returns (uint256) {
        return _getStorage().sumMaxNextClaim[address(collector)][provider];
    }

    /// @inheritdoc IRecurringAgreementManager
    function getEscrowAccount(
        IRecurringCollector collector,
        address provider
    ) external view returns (IPaymentsEscrow.EscrowAccount memory) {
        return PAYMENTS_ESCROW.escrowAccounts(address(this), address(collector), provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function getAgreementMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getStorage().agreements[agreementId].maxNextClaim;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getAgreementInfo(bytes16 agreementId) external view returns (AgreementInfo memory) {
        return _getStorage().agreements[agreementId];
    }

    /// @inheritdoc IRecurringAgreementManager
    function getProviderAgreementCount(address provider) external view returns (uint256) {
        return _getStorage().providerAgreementIds[provider].length();
    }

    /// @inheritdoc IRecurringAgreementManager
    function getProviderAgreements(address provider) external view returns (bytes16[] memory) {
        return _getProviderAgreements(provider, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementManager
    function getProviderAgreements(
        address provider,
        uint256 offset,
        uint256 count
    ) external view returns (bytes16[] memory) {
        return _getProviderAgreements(provider, offset, count);
    }

    /// @inheritdoc IRecurringAgreementManager
    function getEscrowBasis() external view returns (EscrowBasis) {
        return _getStorage().escrowBasis;
    }

    /// @inheritdoc IRecurringAgreementManager
    function sumMaxNextClaimAll() external view returns (uint256) {
        return _getStorage().sumMaxNextClaimAll;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getTotalEscrowDeficit() external view returns (uint256) {
        return _getStorage().totalEscrowDeficit;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getTotalAgreementCount() external view returns (uint256) {
        return _getStorage().totalAgreementCount;
    }

    /// @inheritdoc IRecurringAgreementManager
    function isEnforcedJit() external view returns (bool) {
        return _getStorage().enforcedJit;
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

    function _getProviderAgreements(
        address provider,
        uint256 offset,
        uint256 count
    ) private view returns (bytes16[] memory) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage ids = $.providerAgreementIds[provider];
        uint256 total = ids.length();
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new bytes16[](0);

        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;

        bytes16[] memory result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = bytes16(ids.at(offset + i));

        return result;
    }

    /**
     * @notice Reconcile an agreement and update escrow for its (collector, provider) pair.
     * @param agreementId The agreement ID to reconcile
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAndUpdateEscrow(RecurringAgreementManagerStorage storage $, bytes16 agreementId) private {
        _reconcileAgreement($, agreementId);
        AgreementInfo storage info = $.agreements[agreementId];
        _updateEscrow($, info.collector, info.provider);
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

        // If not yet accepted in RC, keep the pre-offer estimate
        if (rca.state == IRecurringCollector.AgreementState.NotAccepted) return;

        // Clear pending update if it has been applied (updateNonce advanced past pending)
        // solhint-disable-next-line gas-strict-inequalities
        if (agreement.pendingUpdateHash != bytes32(0) && agreement.pendingUpdateNonce <= rca.updateNonce) {
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
        delete $.agreements[agreementId];

        _updateEscrow($, collector, provider);
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

        IRecurringCollector collector = agreement.collector;
        address provider = agreement.provider;
        address c = address(collector);
        uint256 oldDeficit = _providerEscrowDeficit($, collector, provider);

        if (pending) agreement.pendingUpdateMaxNextClaim = newValue;
        else agreement.maxNextClaim = newValue;

        $.sumMaxNextClaim[c][provider] = $.sumMaxNextClaim[c][provider] - oldValue + newValue;
        $.sumMaxNextClaimAll = $.sumMaxNextClaimAll - oldValue + newValue;
        $.totalEscrowDeficit = $.totalEscrowDeficit - oldDeficit + _providerEscrowDeficit($, collector, provider);
    }

    /**
     * @notice Compute escrow levels (min, max) based on escrow basis.
     * @dev Escrow ladder:
     *
     * | Level      | min (deposit floor) | max (thaw ceiling) |
     * |------------|--------------------|--------------------|
     * | Full       | sumMaxNext         | sumMaxNext         |
     * | OnDemand   | 0                  | sumMaxNext         |
     * | JustInTime | 0                  | 0                  |
     *
     * When enforcedJit, behaves as JustInTime regardless of configured basis.
     * Full degrades to OnDemand when totalEscrowDeficit >= available.
     *
     * @param collector The collector contract address
     * @param provider The service provider
     * @return min Deposit floor — deposit if balance is below this
     * @return max Thaw ceiling — thaw if balance is above this
     */
    // solhint-disable-next-line use-natspec
    function _escrowMinMax(
        RecurringAgreementManagerStorage storage $,
        IRecurringCollector collector,
        address provider
    ) private view returns (uint256 min, uint256 max) {
        EscrowBasis basis = $.enforcedJit ? EscrowBasis.JustInTime : $.escrowBasis;

        max = basis == EscrowBasis.JustInTime ? 0 : $.sumMaxNextClaim[address(collector)][provider];
        min = (basis == EscrowBasis.Full && $.totalEscrowDeficit < GRAPH_TOKEN.balanceOf(address(this))) ? max : 0;
    }

    /**
     * @notice Compute a (collector, provider) pair's escrow deficit: max(0, sumMaxNext - snapshot).
     * @param collector The collector contract
     * @param provider The service provider
     * @return deficit The amount not in escrow for this (collector, provider)
     */
    // solhint-disable-next-line use-natspec
    function _providerEscrowDeficit(
        RecurringAgreementManagerStorage storage $,
        IRecurringCollector collector,
        address provider
    ) private view returns (uint256 deficit) {
        address c = address(collector);
        uint256 sumMaxNext = $.sumMaxNextClaim[c][provider];
        uint256 snapshot = $.escrowSnap[c][provider];

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
     * 1. Adjust thaw target — cancel/reduce unrealised thawing to keep effective balance >= min,
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
    function _updateEscrow(
        RecurringAgreementManagerStorage storage $,
        IRecurringCollector collector,
        address provider
    ) private {
        // solhint-disable-next-line gas-strict-inequalities
        if ($.enforcedJit && $.totalEscrowDeficit <= GRAPH_TOKEN.balanceOf(address(this))) {
            $.enforcedJit = false;
            emit EnforcedJitRecovered($.escrowBasis);
        }

        address c = address(collector);
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.escrowAccounts(address(this), c, provider);
        (uint256 min, uint256 max) = _escrowMinMax($, collector, provider);

        uint256 escrowed = account.balance - account.tokensThawing;
        // Objectives in order of priority:
        // We want to end with escrowed of at least min, and seek to thaw down to no more than max.
        // 1. Do not reset thaw timer if a thaw is in progress.
        //    (This is to avoid thrash of restarting thaws resulting in never withdrawing excess.)
        // 2. Make minimal adjustment to thawing tokens to get as close to min/max as possible.
        //    (First cancel unrealised thawing before depositing.)
        uint256 thawTarget = (escrowed < min)
            ? (min < account.balance ? account.balance - min : 0)
            : (max < escrowed ? account.balance - max : account.tokensThawing);
        if (thawTarget != account.tokensThawing) {
            PAYMENTS_ESCROW.thaw(c, provider, thawTarget, false);
            account = PAYMENTS_ESCROW.escrowAccounts(address(this), c, provider);
        }

        _withdrawAndRebalance(c, provider, account, min, max);
        _setEscrowSnap($, collector, provider);
    }

    /**
     * @notice Withdraw completed thaws and rebalance: thaw excess above max or deposit deficit below min.
     * @dev Realised thawing is always withdrawn, even if within [min, max].
     * Then if no thaw is active: thaw any balance above max, or deposit to reach min.
     * These last two steps are mutually exclusive (min <= max). Only one runs per call.
     * @param c Collector address
     * @param provider Service provider address
     * @param account Current escrow account state
     * @param min Deposit floor
     * @param max Thaw ceiling
     */
    function _withdrawAndRebalance(
        address c,
        address provider,
        IPaymentsEscrow.EscrowAccount memory account,
        uint256 min,
        uint256 max
    ) private {
        // Withdraw any remaining thawed tokens (realised thawing is withdrawn even if within [min, max])
        // solhint-disable-next-line gas-strict-inequalities
        if (0 < account.tokensThawing && account.thawEndTimestamp <= block.timestamp) {
            emit EscrowWithdrawn(provider, c, PAYMENTS_ESCROW.withdraw(c, provider));
            account = PAYMENTS_ESCROW.escrowAccounts(address(this), c, provider);
        }

        if (account.tokensThawing == 0) {
            if (max < account.balance)
                // Thaw excess above max (might have withdrawn allowing a new thaw to start)
                PAYMENTS_ESCROW.thaw(c, provider, account.balance - max, false);
            else {
                // Deposit any deficit below min (deposit exactly the missing amount, no more)
                uint256 deposit = (min < account.balance) ? 0 : min - account.balance;
                if (0 < deposit) {
                    GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deposit);
                    PAYMENTS_ESCROW.deposit(c, provider, deposit);
                    emit EscrowFunded(provider, c, deposit);
                }
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
        IRecurringCollector collector,
        address provider
    ) private {
        address c = address(collector);
        uint256 oldEscrow = $.escrowSnap[c][provider];
        uint256 newEscrow = PAYMENTS_ESCROW.escrowAccounts(address(this), c, provider).balance;
        if (oldEscrow == newEscrow) return;

        uint256 oldDeficit = _providerEscrowDeficit($, collector, provider);
        $.escrowSnap[c][provider] = newEscrow;
        uint256 newDeficit = _providerEscrowDeficit($, collector, provider);
        $.totalEscrowDeficit = $.totalEscrowDeficit - oldDeficit + newDeficit;
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
