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

// solhint-disable-next-line no-unused-import
import { ERC165Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol"; // Used by @inheritdoc

/**
 * @title RecurringAgreementManager
 * @author Edge & Node
 * @notice Manages escrow funding for RCAs (Recurring Collection Agreements) using
 * issuance-allocated tokens. This contract:
 *
 * 1. Receives minted GRT from IssuanceAllocator (implements IIssuanceTarget)
 * 2. Authorizes RCA acceptance via contract callback (implements IContractApprover)
 * 3. Tracks max-next-claim per agreement, funds PaymentsEscrow to cover maximums
 *
 * One escrow per (this contract, collector, provider) covers all managed
 * RCAs for that (collector, provider) pair. Each agreement stores its own collector
 * address. Other participants can independently use RCAs via the standard ECDSA-signed flow.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringAgreementManager is BaseUpgradeable, IIssuanceTarget, IContractApprover, IRecurringAgreementManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;

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
        mapping(address collector => mapping(address provider => uint256)) requiredEscrow;
        /// @notice Set of agreement IDs per service provider (stored as bytes32 for EnumerableSet)
        mapping(address provider => EnumerableSet.Bytes32Set) providerAgreementIds;
        /// @notice Governance-configured funding level (not modified by enforced JIT)
        FundingBasis fundingBasis;
        /// @notice Sum of requiredEscrow across all (collector, provider) pairs
        uint256 totalRequiredAll;
        /// @notice Total unfunded escrow: sum of max(0, requiredEscrow[c][p] - lastKnownFunded[c][p])
        uint256 totalUnfunded;
        /// @notice Total number of tracked agreements across all providers
        uint256 totalAgreementCount;
        /// @notice Last known escrow balance per (collector, provider) pair (for snapshot diff)
        mapping(address collector => mapping(address provider => uint256)) lastKnownFunded;
        /// @notice Whether JIT mode is enforced (beforeCollection couldn't fund)
        bool enforcedJit;
        /// @notice Optional oracle for checking payment eligibility of service providers
        IRewardsEligibility paymentEligibilityOracle;
    }

    // solhint-disable-next-line gas-named-return-values
    // keccak256(abi.encode(uint256(keccak256("graphprotocol.issuance.storage.RecurringAgreementManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RECURRING_AGREEMENT_MANAGER_STORAGE_LOCATION =
        0x13814b254ec9c757012be47b3445539ef5e5e946eb9d2ef31ea6d4423bf88b00;

    // -- Constructor --

    /**
     * @notice Constructor for the RecurringAgreementManager contract
     * @param graphToken Address of the Graph Token contract
     * @param paymentsEscrow Address of the PaymentsEscrow contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address graphToken, address paymentsEscrow) BaseUpgradeable(graphToken) {
        PAYMENTS_ESCROW = IPaymentsEscrow(paymentsEscrow);
    }

    // -- Initialization --

    /**
     * @notice Initialize the RecurringAgreementManager contract
     * @param governor Address that will have the GOVERNOR_ROLE
     */
    function initialize(address governor) external virtual initializer {
        __BaseUpgradeable_init(governor);
        _getStorage().fundingBasis = FundingBasis.Full;
    }

    /**
     * @notice Reinitialize for upgrade: set default funding basis to Full
     */
    function initializeV2() external reinitializer(2) {
        _getStorage().fundingBasis = FundingBasis.Full;
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
        address collector = msg.sender;
        require(collector == agreement.collector, OnlyAgreementCollector());

        // Only deposit if escrow is short for this collection
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.escrowAccounts(
            address(this),
            collector,
            provider
        );
        if (tokensToCollect < account.balance) return;

        uint256 deficit = tokensToCollect - account.balance;
        if (deficit < GRAPH_TOKEN.balanceOf(address(this))) {
            GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), deficit);
            PAYMENTS_ESCROW.deposit(collector, provider, deficit);
        } else if (!$.enforcedJit) {
            $.enforcedJit = true;
            emit EnforcedJit($.fundingBasis);
        }
    }

    /// @inheritdoc IContractApprover
    function afterCollection(bytes16 agreementId, uint256 /* tokensCollected */) external override {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        if (info.provider == address(0)) return;
        require(msg.sender == info.collector, OnlyAgreementCollector());

        _reconcileAgreement($, agreementId);
        _updateEscrow($, info.collector, info.provider);
    }

    // -- IRecurringAgreementManager: Core Functions --

    /// @inheritdoc IRecurringAgreementManager
    function offerAgreement(
        IRecurringCollector.RecurringCollectionAgreement calldata rca,
        address collector
    ) external onlyRole(OPERATOR_ROLE) whenNotPaused returns (bytes16 agreementId) {
        require(rca.payer == address(this), PayerMustBeManager(rca.payer, address(this)));
        require(rca.serviceProvider != address(0), ServiceProviderZeroAddress());
        require(rca.dataService != address(0), DataServiceZeroAddress());
        require(collector != address(0), CollectorZeroAddress());

        RecurringAgreementManagerStorage storage $ = _getStorage();

        agreementId = IRecurringCollector(collector).generateAgreementId(
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
        bytes32 agreementHash = IRecurringCollector(collector).hashRCA(rca);
        $.authorizedHashes[agreementHash] = agreementId;

        // Store agreement tracking data (maxNextClaim set to 0; _setAgreementRequired handles accounting)
        $.agreements[agreementId] = AgreementInfo({
            provider: rca.serviceProvider,
            deadline: rca.deadline,
            dataService: rca.dataService,
            pendingUpdateNonce: 0,
            maxNextClaim: 0,
            pendingUpdateMaxNextClaim: 0,
            agreementHash: agreementHash,
            pendingUpdateHash: bytes32(0),
            collector: collector
        });
        $.providerAgreementIds[rca.serviceProvider].add(bytes32(agreementId));
        _setAgreementRequired($, agreementId, maxNextClaim, false);
        $.totalAgreementCount += 1;

        // Update escrow: fund deficit (partial-cancel thaw if needed), thaw excess
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

        // Calculate pending max next claim from RCAU parameters (conservative: includes initial + ongoing)
        uint256 pendingMaxNextClaim = rcau.maxOngoingTokensPerSecond * rcau.maxSecondsPerCollection +
            rcau.maxInitialTokens;

        // Clean up old pending hash if replacing
        if (agreement.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[agreement.pendingUpdateHash];
        }

        // Authorize the RCAU hash for the IContractApprover callback
        bytes32 updateHash = IRecurringCollector(agreement.collector).hashRCAU(rcau);
        $.authorizedHashes[updateHash] = agreementId;

        // Update pending tracking — _setAgreementRequired handles escrow accounting
        _setAgreementRequired($, agreementId, pendingMaxNextClaim, true);
        agreement.pendingUpdateNonce = rcau.nonce;
        agreement.pendingUpdateHash = updateHash;

        // Update escrow: fund deficit (partial-cancel thaw if needed), thaw excess
        _updateEscrow($, agreement.collector, agreement.provider);

        emit AgreementUpdateOffered(agreementId, pendingMaxNextClaim, rcau.nonce);
    }

    /// @inheritdoc IRecurringAgreementManager
    function revokeOffer(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        // Only revoke un-accepted agreements — accepted ones must be canceled via cancelAgreement
        IRecurringCollector.AgreementData memory agreement = IRecurringCollector(info.collector).getAgreement(
            agreementId
        );
        require(
            agreement.state == IRecurringCollector.AgreementState.NotAccepted,
            AgreementAlreadyAccepted(agreementId)
        );

        address provider = info.provider;
        address collector = info.collector;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Zero out escrow requirements before deleting
        _setAgreementRequired($, agreementId, 0, false);
        _setAgreementRequired($, agreementId, 0, true);
        $.totalAgreementCount -= 1;
        $.providerAgreementIds[provider].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit OfferRevoked(agreementId, provider);
        _updateEscrow($, collector, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function cancelAgreement(bytes16 agreementId) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        IRecurringCollector.AgreementData memory agreement = IRecurringCollector(info.collector).getAgreement(
            agreementId
        );

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
        _updateEscrow($, info.collector, info.provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function removeAgreement(bytes16 agreementId) external {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        // Re-read from the agreement's collector to get current state
        IRecurringCollector rc = IRecurringCollector(info.collector);
        IRecurringCollector.AgreementData memory agreement = rc.getAgreement(agreementId);

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
            currentMaxClaim = rc.getMaxNextClaim(agreementId);
        }
        require(currentMaxClaim == 0, AgreementStillClaimable(agreementId, currentMaxClaim));

        address provider = info.provider;
        address collector = info.collector;

        // Clean up authorized hashes
        delete $.authorizedHashes[info.agreementHash];
        if (info.pendingUpdateHash != bytes32(0)) {
            delete $.authorizedHashes[info.pendingUpdateHash];
        }

        // Zero out escrow requirements before deleting
        _setAgreementRequired($, agreementId, 0, false);
        _setAgreementRequired($, agreementId, 0, true);
        $.totalAgreementCount -= 1;
        $.providerAgreementIds[provider].remove(bytes32(agreementId));
        delete $.agreements[agreementId];

        emit AgreementRemoved(agreementId, provider);
        _updateEscrow($, collector, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function reconcileAgreement(bytes16 agreementId) external {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        AgreementInfo storage info = $.agreements[agreementId];
        require(info.provider != address(0), AgreementNotOffered(agreementId));

        _reconcileAgreement($, agreementId);
        _updateEscrow($, info.collector, info.provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function updateEscrow(address collector, address provider) external {
        _updateEscrow(_getStorage(), collector, provider);
    }

    /// @inheritdoc IRecurringAgreementManager
    function setFundingBasis(FundingBasis basis) external onlyRole(GOVERNOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        FundingBasis oldBasis = $.fundingBasis;
        $.fundingBasis = basis;
        $.enforcedJit = false;
        emit FundingBasisChanged(oldBasis, basis);
    }

    /// @inheritdoc IRecurringAgreementManager
    function setPaymentEligibilityOracle(address oracle) external onlyRole(GOVERNOR_ROLE) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        address oldOracle = address($.paymentEligibilityOracle);
        $.paymentEligibilityOracle = IRewardsEligibility(oracle);
        emit PaymentEligibilityOracleSet(oldOracle, oracle);
    }

    // -- IRewardsEligibility --

    /**
     * @notice Check if a service provider is eligible for payment collection.
     * @dev When no oracle is configured (address(0)), all providers are eligible.
     * When an oracle is set, delegates to the oracle's isEligible check.
     * @param serviceProvider The address of the service provider
     * @return True if the service provider is eligible
     */
    function isEligible(address serviceProvider) external view returns (bool) {
        IRewardsEligibility oracle = _getStorage().paymentEligibilityOracle;
        if (address(oracle) == address(0)) return true;
        return oracle.isEligible(serviceProvider);
    }

    // -- IRecurringAgreementManager: View Functions --

    /// @inheritdoc IRecurringAgreementManager
    function getRequiredEscrow(address collector, address provider) external view returns (uint256) {
        return _getStorage().requiredEscrow[collector][provider];
    }

    /// @inheritdoc IRecurringAgreementManager
    function getDeficit(address collector, address provider) external view returns (uint256) {
        RecurringAgreementManagerStorage storage $ = _getStorage();
        uint256 required = $.requiredEscrow[collector][provider];
        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.escrowAccounts(
            address(this),
            collector,
            provider
        );
        uint256 currentBalance = account.balance - account.tokensThawing;
        if (currentBalance < required) {
            return required - currentBalance;
        }
        return 0;
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
        RecurringAgreementManagerStorage storage $ = _getStorage();
        EnumerableSet.Bytes32Set storage ids = $.providerAgreementIds[provider];
        uint256 count = ids.length();
        bytes16[] memory result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) {
            result[i] = bytes16(ids.at(i));
        }
        return result;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getFundingBasis() external view returns (FundingBasis) {
        return _getStorage().fundingBasis;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getTotalRequired() external view returns (uint256) {
        return _getStorage().totalRequiredAll;
    }

    /// @inheritdoc IRecurringAgreementManager
    function getTotalUnfunded() external view returns (uint256) {
        return _getStorage().totalUnfunded;
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
     * @notice Reconcile a single agreement's max next claim against on-chain state
     * @param agreementId The agreement ID to reconcile
     */
    // solhint-disable-next-line use-natspec
    function _reconcileAgreement(RecurringAgreementManagerStorage storage $, bytes16 agreementId) private {
        AgreementInfo storage info = $.agreements[agreementId];

        IRecurringCollector rc = IRecurringCollector(info.collector);
        IRecurringCollector.AgreementData memory agreement = rc.getAgreement(agreementId);

        // If not yet accepted in RC, keep the pre-offer estimate
        if (agreement.state == IRecurringCollector.AgreementState.NotAccepted) {
            return;
        }

        // Clear pending update if it has been applied (updateNonce advanced past pending)
        // solhint-disable-next-line gas-strict-inequalities
        if (info.pendingUpdateHash != bytes32(0) && info.pendingUpdateNonce <= agreement.updateNonce) {
            _setAgreementRequired($, agreementId, 0, true);
            delete $.authorizedHashes[info.pendingUpdateHash];
            info.pendingUpdateNonce = 0;
            info.pendingUpdateHash = bytes32(0);
        }

        uint256 oldMaxClaim = info.maxNextClaim;
        uint256 newMaxClaim = rc.getMaxNextClaim(agreementId);

        if (oldMaxClaim != newMaxClaim) {
            _setAgreementRequired($, agreementId, newMaxClaim, false);
            emit AgreementReconciled(agreementId, oldMaxClaim, newMaxClaim);
        }
    }

    /**
     * @notice Atomically set one escrow obligation slot of an agreement and cascade to provider/global totals.
     * @dev This and {_setFundedSnapshot} are the only two functions that mutate totalUnfunded.
     * @param agreementId The agreement to update
     * @param newValue The new obligation value
     * @param pending If true, updates pendingUpdateMaxNextClaim; otherwise updates maxNextClaim
     */
    // solhint-disable-next-line use-natspec
    function _setAgreementRequired(
        RecurringAgreementManagerStorage storage $,
        bytes16 agreementId,
        uint256 newValue,
        bool pending
    ) private {
        AgreementInfo storage info = $.agreements[agreementId];
        address collector = info.collector;
        address provider = info.provider;
        uint256 oldUnfunded = _providerUnfunded($, collector, provider);

        uint256 oldValue;
        if (pending) {
            oldValue = info.pendingUpdateMaxNextClaim;
            info.pendingUpdateMaxNextClaim = newValue;
        } else {
            oldValue = info.maxNextClaim;
            info.maxNextClaim = newValue;
        }

        $.requiredEscrow[collector][provider] = $.requiredEscrow[collector][provider] - oldValue + newValue;
        $.totalRequiredAll = $.totalRequiredAll - oldValue + newValue;
        $.totalUnfunded = $.totalUnfunded - oldUnfunded + _providerUnfunded($, collector, provider);
    }

    /**
     * @notice Compute deposit target and thaw ceiling based on funding basis.
     * @dev Funding ladder:
     *
     * | Level      | Deposit target | Thaw ceiling |
     * |------------|---------------|-------------|
     * | Full       | required      | required    |
     * | OnDemand   | 0             | required    |
     * | JustInTime | 0             | 0           |
     *
     * When enforcedJit, behaves as JustInTime regardless of configured basis.
     * Full degrades to OnDemand when totalUnfunded > available.
     *
     * @param required The requiredEscrow for this (collector, provider) pair
     * @return depositTarget The target for deposits (deposit if balance is below)
     * @return thawCeiling The ceiling for thaws (thaw if balance is above)
     */
    // solhint-disable-next-line use-natspec
    function _fundingTargets(
        RecurringAgreementManagerStorage storage $,
        uint256 required
    ) private view returns (uint256 depositTarget, uint256 thawCeiling) {
        FundingBasis basis = $.enforcedJit ? FundingBasis.JustInTime : $.fundingBasis;

        depositTarget = (basis == FundingBasis.Full && $.totalUnfunded <= GRAPH_TOKEN.balanceOf(address(this)))
            ? required
            : 0;
        thawCeiling = basis == FundingBasis.JustInTime ? 0 : required;
    }

    /**
     * @notice Compute a (collector, provider) pair's unfunded escrow: max(0, required - funded).
     * @param collector The collector contract
     * @param provider The service provider
     * @return The unfunded amount for this (collector, provider)
     */
    // solhint-disable-next-line use-natspec
    function _providerUnfunded(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private view returns (uint256) {
        uint256 required = $.requiredEscrow[collector][provider];
        uint256 funded = $.lastKnownFunded[collector][provider];
        if (required <= funded) return 0;
        return required - funded;
    }

    /**
     * @notice Update escrow state for a (collector, provider) pair: withdraw completed thaws,
     * fund any deficit, and thaw excess balance.
     * @dev Sequential state normalization using two targets from {_fundingTargets}:
     * - depositTarget: deposit if balance is below this
     * - thawCeiling: thaw if balance is above this
     *
     * Phases:
     * 1. Withdraw completed thaw (skip when escrow is short — cancelThaw avoids round-trip)
     * 2. Reduce thaw if effective balance (balance - thawing) is below thawCeiling
     * 3. Not thawing: start thaw for excess above thawCeiling or deposit for deficit below depositTarget
     *
     * Uses per-call approve (not infinite allowance). Safe because PaymentsEscrow
     * is a trusted protocol contract that transfers exactly the approved amount.
     *
     * Updates funded snapshot at the end for global tracking.
     *
     * @param collector The collector contract address
     * @param provider The service provider to update escrow for
     */
    // solhint-disable-next-line use-natspec
    function _updateEscrow(RecurringAgreementManagerStorage storage $, address collector, address provider) private {
        // Enforced JIT recovery: clear when RAM can afford totalUnfunded
        if ($.enforcedJit) {
            uint256 available = GRAPH_TOKEN.balanceOf(address(this));
            if ($.totalUnfunded <= available) {
                $.enforcedJit = false;
                emit EnforcedJitRecovered($.fundingBasis);
            }
        }

        IPaymentsEscrow.EscrowAccount memory account = PAYMENTS_ESCROW.escrowAccounts(
            address(this),
            collector,
            provider
        );
        uint256 required = $.requiredEscrow[collector][provider];
        (uint256 depositTarget, uint256 thawCeiling) = _fundingTargets($, required);

        // Withdraw completed thaw (skip when escrow is short — step 2 cancels thaw instead)
        bool thawReady = 0 < account.thawEndTimestamp && account.thawEndTimestamp < block.timestamp;
        if (thawReady && depositTarget < account.balance) {
            uint256 withdrawn = PAYMENTS_ESCROW.withdraw(collector, provider);
            emit EscrowWithdrawn(provider, collector, withdrawn);
            account = PAYMENTS_ESCROW.escrowAccounts(address(this), collector, provider);
        }

        // Reduce thaw if effective balance is below thawCeiling; else thawing at acceptable level
        if (0 < account.tokensThawing)
            if (account.balance - account.tokensThawing < thawCeiling) {
                uint256 target = account.balance < thawCeiling ? 0 : account.balance - thawCeiling;
                PAYMENTS_ESCROW.thaw(collector, provider, target, false);
                // solhint-disable-next-line gas-strict-inequalities
                if (depositTarget <= account.balance) {
                    _setFundedSnapshot($, collector, provider);
                    return;
                }
                // thaw cancelled; fall through to deposit below
            } else {
                _setFundedSnapshot($, collector, provider);
                return;
            }

        // Not thawing: thaw excess or deposit deficit
        if (thawCeiling < account.balance) {
            uint256 excess = account.balance - thawCeiling;
            PAYMENTS_ESCROW.thaw(collector, provider, excess, false);
        } else if (account.balance < depositTarget) {
            uint256 deficit = depositTarget - account.balance;
            uint256 available = GRAPH_TOKEN.balanceOf(address(this));
            uint256 toDeposit = deficit < available ? deficit : available;
            if (0 < toDeposit) {
                GRAPH_TOKEN.approve(address(PAYMENTS_ESCROW), toDeposit);
                PAYMENTS_ESCROW.deposit(collector, provider, toDeposit);
                emit EscrowFunded(provider, collector, toDeposit);
            }
        }

        _setFundedSnapshot($, collector, provider);
    }

    /**
     * @notice Atomically sync the funded snapshot for a (collector, provider) pair after escrow mutations.
     * @dev This and {_setAgreementRequired} are the only two functions that mutate totalUnfunded.
     * @param collector The collector address
     * @param provider The service provider
     */
    // solhint-disable-next-line use-natspec
    function _setFundedSnapshot(
        RecurringAgreementManagerStorage storage $,
        address collector,
        address provider
    ) private {
        uint256 oldUnfunded = _providerUnfunded($, collector, provider);
        uint256 currentFunded = PAYMENTS_ESCROW.escrowAccounts(address(this), collector, provider).balance;
        $.lastKnownFunded[collector][provider] = currentFunded;
        uint256 newUnfunded = _providerUnfunded($, collector, provider);
        $.totalUnfunded = $.totalUnfunded - oldUnfunded + newUnfunded;
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
