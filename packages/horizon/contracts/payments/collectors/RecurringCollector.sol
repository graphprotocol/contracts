// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";
import { IAgreementStateChangeCallback } from "@graphprotocol/interfaces/contracts/horizon/IAgreementStateChangeCallback.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol";
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import {
    REGISTERED,
    ACCEPTED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    BY_DATA_SERVICE,
    UPDATE,
    AUTO_UPDATE,
    AUTO_UPDATED,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    WITH_NOTICE,
    IF_NOT_ACCEPTED,
    IAgreementCollector
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPausableControl } from "@graphprotocol/interfaces/contracts/issuance/common/IPausableControl.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

/**
 * @title RecurringCollector contract
 * @author Edge & Node
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCA (Recurring Collection Agreement).
 *
 * Callback model: lifecycle ({IAgreementStateChangeCallback}), collection
 * ({IAgreementOwner.beforeCollection} / {IAgreementOwner.afterCollection}), and eligibility
 * ({IProviderEligibility.isEligible}) callbacks are skipped when the target is `msg.sender`.
 * The caller already has execution context and can sequence its own update logic
 * (e.g. reconciliation, escrow top-up) without a callback. This eliminates callback
 * loops, simplifies reentrancy analysis, and reduces the trust surface between caller
 * and collector. Exception: the data service's {IDataServiceAgreements.acceptAgreement}
 * callback is always invoked (including during auto-update when the data service is
 * `msg.sender`), because it must validate and set up domain-specific state.
 *
 * @custom:security-pause This contract is independently pausable from RecurringAgreementManager.
 * Pausing is an emergency measure for when something is seriously broken and may require an
 * emergency contract upgrade to restore operation. When paused, all state-changing operations
 * are blocked: {collect}, {offer}, {accept}, and {cancel}. View functions remain available.
 * Pause guardians can pause/unpause; the governor manages pause guardian assignments.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is
    GraphDirectory,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    IPausableControl,
    IRecurringCollector
{
    using PPMMath for uint256;

    // -- Constants --

    /// @notice The minimum number of seconds that must be between two collections
    uint32 public constant MIN_SECONDS_COLLECTION_WINDOW = 600;

    /// @notice Maximum gas forwarded to external callbacks (payer and data-service).
    /// Caps gas available to callback implementations, preventing 63/64-rule gas siphoning
    /// attacks that could starve the core collect() / accept() call of gas.
    uint256 private constant MAX_CALLBACK_GAS = 1_500_000;

    /* solhint-disable gas-small-strings */
    /// @notice The typehash for the RecurringCollectionAgreement struct
    bytes32 public constant RCA_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreement(uint64 deadline,uint64 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint32 minSecondsPayerCancellationNotice,uint256 nonce,bytes metadata)"
        );

    /// @notice The typehash for the RecurringCollectionAgreementUpdate struct
    bytes32 public constant RCAU_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint32 minSecondsPayerCancellationNotice,uint32 nonce,bytes metadata)"
        );
    /* solhint-enable gas-small-strings */

    /// @notice Bitmask: include active terms in getMaxNextClaim
    uint8 public constant CLAIM_SCOPE_ACTIVE = 1;
    /// @notice Bitmask: include pending terms in getMaxNextClaim
    uint8 public constant CLAIM_SCOPE_PENDING = 2;

    /// @notice Condition flag: agreement requires eligibility checks before collection
    uint16 public constant CONDITION_ELIGIBILITY_CHECK = 1;

    // -- Internal types --

    /**
     * @dev Internal storage layout for an agreement. Not part of the public interface;
     * callers receive an AgreementData from getAgreementData().
     * Packed layout (3 base slots + nested terms + per-version nonces):
     *   slot 0: dataService(20) + acceptedAt(8) + updateNonce(4) = 32B
     *   slot 1: payer(20) + lastCollectionAt(8) + state(2) = 30B
     *   slot 2: serviceProvider(20) + collectableUntil(8) = 28B
     *   slot 3+: activeTerms (4 fixed slots + dynamic)
     *   slot 7+: pendingTerms (4 fixed slots + dynamic)
     *   slot N:  activeOfferNonce(32)
     *   slot N+1: pendingOfferNonce(32)
     */
    struct AgreementStorage {
        address dataService;
        uint64 acceptedAt;
        uint32 updateNonce;
        address payer;
        uint64 lastCollectionAt;
        uint16 state;
        address serviceProvider;
        uint64 collectableUntil;
        AgreementTerms activeTerms;
        AgreementTerms pendingTerms;
        uint256 activeOfferNonce;
        uint256 pendingOfferNonce;
    }

    // -- State --

    /// @custom:storage-location erc7201:graphprotocol.storage.RecurringCollector
    struct RecurringCollectorStorage {
        /// @notice Tracks agreements
        mapping(bytes16 agreementId => AgreementStorage data) agreements;
        /// @notice List of pause guardians and their allowed status
        mapping(address pauseGuardian => bool allowed) pauseGuardians;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.RecurringCollector")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RECURRING_COLLECTOR_STORAGE_LOCATION =
        0x436d179d846767cf46c6cda3ec5a404bcbe1b4351ce320082402e5e9ab4d6600;

    /**
     * @notice Checks if the caller is a pause guardian.
     */
    modifier onlyPauseGuardian() {
        _checkPauseGuardian();
        _;
    }

    // -- Constructor --

    /**
     * @notice Constructs a new instance of the RecurringCollector implementation contract.
     * @dev Immutables are set here; proxy state is initialized via {initialize}.
     * @param controller The address of the Graph controller.
     */
    constructor(address controller) GraphDirectory(controller) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract (proxy storage).
     * @dev Marks the proxy as initialized so the `initializer` modifier prevents re-entry.
     */
    function initialize() external initializer {
        __Pausable_init();
    }

    // -- External mutating --

    /// @inheritdoc IPausableControl
    function pause() external override onlyPauseGuardian {
        _pause();
    }

    /// @inheritdoc IPausableControl
    function unpause() external override onlyPauseGuardian {
        _unpause();
    }

    /**
     * @notice Sets a pause guardian.
     * @dev Only callable by the governor.
     * @param _pauseGuardian The address of the pause guardian
     * @param _allowed Whether the address should be a pause guardian
     */
    function setPauseGuardian(address _pauseGuardian, bool _allowed) external {
        require(msg.sender == _graphController().getGovernor(), NotGovernor(msg.sender));
        RecurringCollectorStorage storage $ = _getStorage();

        if ($.pauseGuardians[_pauseGuardian] == _allowed) return;

        $.pauseGuardians[_pauseGuardian] = _allowed;
        emit PauseGuardianSet(_pauseGuardian, _allowed);
    }

    /**
     * @inheritdoc IPaymentsCollector
     * @dev Caller must be the data service the RCA was issued to.
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    ) external nonReentrant whenNotPaused returns (uint256) {
        try this.decodeCollectData(data) returns (CollectParams memory collectParams) {
            return _collect(paymentType, collectParams);
        } catch {
            revert InvalidCollectData(data);
        }
    }

    /// @inheritdoc IRecurringCollector
    function offer(
        uint8 offerType,
        bytes calldata data,
        uint16 options
    ) external nonReentrant whenNotPaused returns (OfferResult memory result) {
        if (offerType == OFFER_TYPE_NEW) {
            RecurringCollectionAgreement memory rca = abi.decode(data, (RecurringCollectionAgreement));
            require(msg.sender == rca.payer, UnauthorizedPayer(msg.sender, rca.payer));
            (result.agreementId, result.versionHash) = _validateAndStoreOffer(rca);
            result.dataService = rca.dataService;
            result.serviceProvider = rca.serviceProvider;
            result.state = REGISTERED;
        } else if (offerType == OFFER_TYPE_UPDATE) {
            RecurringCollectionAgreementUpdate memory rcau = abi.decode(data, (RecurringCollectionAgreementUpdate));
            AgreementStorage storage agreement = _getAgreementStorage(rcau.agreementId);
            require(msg.sender == agreement.payer, UnauthorizedPayer(msg.sender, agreement.payer));
            return _validateAndStoreUpdate(agreement, rcau, options);
        } else {
            revert InvalidOfferType(offerType);
        }
    }

    /// @inheritdoc IRecurringCollector
    function accept(
        bytes16 agreementId,
        bytes32 versionHash,
        bytes calldata extraData,
        uint16 options
    ) external nonReentrant whenNotPaused {
        AgreementStorage storage agreement = _getAgreementStorage(agreementId);
        uint16 state = agreement.state;

        require(
            msg.sender == agreement.serviceProvider,
            UnauthorizedServiceProvider(msg.sender, agreement.serviceProvider)
        );

        if (state & (REGISTERED | ACCEPTED) == REGISTERED)
            _accept(agreementId, versionHash, extraData, agreement, agreement.activeTerms, false, false, options);
        else if (state & ACCEPTED != 0)
            // Accept pending terms — allowed even if NOTICE_GIVEN, SETTLED, BY_*
            _accept(agreementId, versionHash, extraData, agreement, agreement.pendingTerms, false, false, options);
        else revert AgreementIncorrectState(agreementId, state);
    }

    /// @inheritdoc IAgreementCollector
    function cancel(bytes16 agreementId, bytes32 versionHash, uint16 options) external nonReentrant whenNotPaused {
        AgreementStorage storage agreement = _getAgreementStorage(agreementId);

        uint16 byFlag;
        if (agreement.payer == msg.sender) byFlag = BY_PAYER;
        else if (agreement.serviceProvider == msg.sender) byFlag = BY_PROVIDER;
        else if (agreement.dataService == msg.sender) byFlag = BY_DATA_SERVICE;
        else revert UnauthorizedCaller(msg.sender, address(0));

        uint16 eventState;
        if (versionHash == agreement.pendingTerms.hash) {
            delete agreement.pendingTerms;
            // UPDATE in event only — signals this cancel targets pending terms.
            // Not persisted: agreement lifecycle state is unchanged.
            eventState = agreement.state | UPDATE;
        } else {
            require(
                versionHash == agreement.activeTerms.hash,
                AgreementHashMismatch(agreementId, agreement.activeTerms.hash, versionHash)
            );
            uint16 oldState = agreement.state;
            require(oldState & REGISTERED != 0, AgreementIncorrectState(agreementId, oldState));

            if (options & IF_NOT_ACCEPTED != 0)
                require(oldState & ACCEPTED == 0, AgreementIncorrectState(agreementId, oldState));

            if (byFlag == BY_PAYER && (oldState & ACCEPTED != 0)) {
                _applyNotice(
                    agreement,
                    agreementId,
                    uint64(block.timestamp) + agreement.activeTerms.minSecondsPayerCancellationNotice
                );
            } else {
                uint64 noticeCutoff = uint64(block.timestamp);
                if (noticeCutoff < agreement.collectableUntil) agreement.collectableUntil = noticeCutoff;
            }

            eventState = oldState | NOTICE_GIVEN | byFlag;
            if (oldState & ACCEPTED == 0) eventState = eventState | SETTLED;
            agreement.state = eventState;
        }

        _emitAndNotify(agreementId, versionHash, eventState, agreement.dataService, agreement.payer);
    }

    // -- External view --

    /// @inheritdoc IRecurringCollector
    function getAgreementData(bytes16 agreementId) external view returns (AgreementData memory data_) {
        AgreementStorage storage a = _getAgreementStorage(agreementId);
        data_.agreementId = agreementId;
        data_.payer = a.payer;
        data_.serviceProvider = a.serviceProvider;
        data_.dataService = a.dataService;
        data_.acceptedAt = a.acceptedAt;
        data_.lastCollectionAt = a.lastCollectionAt;
        data_.collectableUntil = a.collectableUntil;
        data_.updateNonce = a.updateNonce;
        data_.state = a.state;
        (data_.isCollectable, data_.collectionSeconds, ) = _getCollectionInfo(
            a.state,
            a.collectableUntil,
            a.lastCollectionAt,
            a.acceptedAt,
            a.activeTerms.maxSecondsPerCollection
        );
    }

    /// @inheritdoc IRecurringCollector
    function getAgreementVersionCount(bytes16 agreementId) external view returns (uint256) {
        AgreementStorage storage agreement = _getAgreementStorage(agreementId);
        if (agreement.activeTerms.hash == bytes32(0)) return 0;
        if (agreement.pendingTerms.hash == bytes32(0)) return 1;
        return 2;
    }

    /// @inheritdoc IAgreementCollector
    function getAgreementVersionAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (AgreementVersion memory version) {
        AgreementStorage storage agreement = _getAgreementStorage(agreementId);
        version.agreementId = agreementId;
        version.state = agreement.state;

        if (index == 0) version.versionHash = agreement.activeTerms.hash;
        else if (index == 1) {
            version.versionHash = agreement.pendingTerms.hash;
            version.state = version.state | UPDATE;
        }
    }

    /* solhint-disable function-max-lines */
    /// @inheritdoc IRecurringCollector
    function getAgreementOfferAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (uint8 offerType, bytes memory offerData) {
        AgreementStorage storage agreement = _getAgreementStorage(agreementId);

        AgreementTerms storage terms;
        uint256 offerNonce;
        bool isUpdate;

        if (index == 0) {
            terms = agreement.activeTerms;
            offerNonce = agreement.activeOfferNonce;
            isUpdate = (agreement.state & UPDATE) != 0;
        } else if (index == 1) {
            terms = agreement.pendingTerms;
            offerNonce = agreement.pendingOfferNonce;
            isUpdate = true; // pending is always an update
        } else {
            return (0, "");
        }

        if (terms.hash == bytes32(0)) return (0, "");

        if (isUpdate) {
            offerType = OFFER_TYPE_UPDATE;
            offerData = abi.encode(
                RecurringCollectionAgreementUpdate({
                    agreementId: agreementId,
                    deadline: terms.deadline,
                    endsAt: terms.endsAt,
                    maxInitialTokens: terms.maxInitialTokens,
                    maxOngoingTokensPerSecond: terms.maxOngoingTokensPerSecond,
                    minSecondsPerCollection: terms.minSecondsPerCollection,
                    maxSecondsPerCollection: terms.maxSecondsPerCollection,
                    conditions: terms.conditions,
                    minSecondsPayerCancellationNotice: terms.minSecondsPayerCancellationNotice,
                    // Safe: pendingOfferNonce always originates from RCAU.nonce (uint32).
                    // activeOfferNonce reaches this branch only when isUpdate is true
                    // (UPDATE flag set on state), meaning it was promoted from pendingOfferNonce.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    nonce: uint32(offerNonce),
                    metadata: terms.metadata
                })
            );
        } else {
            offerType = OFFER_TYPE_NEW;
            offerData = abi.encode(
                RecurringCollectionAgreement({
                    deadline: terms.deadline,
                    endsAt: terms.endsAt,
                    payer: agreement.payer,
                    dataService: agreement.dataService,
                    serviceProvider: agreement.serviceProvider,
                    maxInitialTokens: terms.maxInitialTokens,
                    maxOngoingTokensPerSecond: terms.maxOngoingTokensPerSecond,
                    minSecondsPerCollection: terms.minSecondsPerCollection,
                    maxSecondsPerCollection: terms.maxSecondsPerCollection,
                    conditions: terms.conditions,
                    minSecondsPayerCancellationNotice: terms.minSecondsPayerCancellationNotice,
                    nonce: offerNonce,
                    metadata: terms.metadata
                })
            );
        }
    }
    /* solhint-enable function-max-lines */

    /// @inheritdoc IRecurringCollector
    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getMaxNextClaim(agreementId, CLAIM_SCOPE_ACTIVE | CLAIM_SCOPE_PENDING);
    }

    /// @inheritdoc IRecurringCollector
    function getMaxNextClaim(bytes16 agreementId, uint8 claimScope) external view returns (uint256) {
        return _getMaxNextClaim(agreementId, claimScope);
    }

    /// @inheritdoc IRecurringCollector
    function generateAgreementId(
        address payer,
        address dataService,
        address serviceProvider,
        uint64 deadline,
        uint256 nonce
    ) external pure returns (bytes16) {
        return _generateAgreementId(payer, dataService, serviceProvider, deadline, nonce);
    }

    // -- Public view --

    /**
     * @notice List of pause guardians and their allowed status
     * @param pauseGuardian The address to check
     * @return Whether the address is a pause guardian
     */
    function isPauseGuardian(address pauseGuardian) public view override returns (bool) {
        return _getStorage().pauseGuardians[pauseGuardian];
    }

    /// @inheritdoc IPausableControl
    function paused() public view override(PausableUpgradeable, IPausableControl) returns (bool) {
        return super.paused();
    }

    // -- Public pure --

    /**
     * @notice Decodes the collect data.
     * @param data The encoded collect parameters.
     * @return The decoded collect parameters.
     */
    function decodeCollectData(bytes calldata data) public pure returns (CollectParams memory) {
        return abi.decode(data, (CollectParams));
    }

    /**
     * @notice Compute the struct hash for an RCA.
     * @param rca The RCA to hash
     * @return The struct hash
     */
    function hashRCA(RecurringCollectionAgreement memory rca) public pure returns (bytes32) {
        // forge-lint: disable-start(asm-keccak256)
        // Split abi.encode to avoid stack-too-deep with 14 fields
        bytes memory metadataHash = abi.encode(keccak256(rca.metadata));
        return
            keccak256(
                bytes.concat(
                    abi.encode(
                        RCA_TYPEHASH,
                        rca.deadline,
                        rca.endsAt,
                        rca.payer,
                        rca.dataService,
                        rca.serviceProvider,
                        rca.maxInitialTokens,
                        rca.maxOngoingTokensPerSecond
                    ),
                    abi.encode(
                        rca.minSecondsPerCollection,
                        rca.maxSecondsPerCollection,
                        rca.conditions,
                        rca.minSecondsPayerCancellationNotice,
                        rca.nonce
                    ),
                    metadataHash
                )
            );
        // forge-lint: disable-end(asm-keccak256)
    }

    /**
     * @notice Compute the struct hash for an RCAU.
     * @param rcau The RCAU to hash
     * @return The struct hash
     */
    function hashRCAU(RecurringCollectionAgreementUpdate memory rcau) public pure returns (bytes32) {
        // forge-lint: disable-start(asm-keccak256)
        return
            keccak256(
                abi.encode(
                    RCAU_TYPEHASH,
                    rcau.agreementId,
                    rcau.deadline,
                    rcau.endsAt,
                    rcau.maxInitialTokens,
                    rcau.maxOngoingTokensPerSecond,
                    rcau.minSecondsPerCollection,
                    rcau.maxSecondsPerCollection,
                    rcau.conditions,
                    rcau.minSecondsPayerCancellationNotice,
                    rcau.nonce,
                    keccak256(rcau.metadata)
                )
            );
        // forge-lint: disable-end(asm-keccak256)
    }

    // -- Internal --

    function _checkPauseGuardian() internal view {
        require(_getStorage().pauseGuardians[msg.sender], NotPauseGuardian(msg.sender));
    }

    // -- Private mutating --

    /* solhint-disable function-max-lines */
    /**
     * @notice Collect payment through the payments protocol.
     * @dev Caller must be the data service the RCA was issued to.
     *
     * `_params.tokens` is the data service's requested amount — an upper bound, not a guarantee.
     * The actual payout is `min(_params.tokens, maxOngoingTokensPerSecond * collectionSeconds
     * [+ maxInitialTokens on first collection])`, where `collectionSeconds` is already capped at
     * `maxSecondsPerCollection` by `_getCollectionInfo`.
     *
     * Temporal validation (`minSecondsPerCollection`) is enforced unconditionally, even when
     * `_params.tokens` is zero, to prevent bypassing collection windows while updating
     * `lastCollectionAt`.
     *
     * Emits {RCACollected} event.
     *
     * @param _paymentType The type of payment to collect
     * @param _params The decoded parameters for the collection
     * @return The amount of tokens collected
     */
    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        CollectParams memory _params
    ) private returns (uint256) {
        AgreementStorage storage agreement = _getAgreementStorage(_params.agreementId);

        // Check if agreement is collectable first
        (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason) = _getCollectionInfo(
            agreement.state,
            agreement.collectableUntil,
            agreement.lastCollectionAt,
            agreement.acceptedAt,
            agreement.activeTerms.maxSecondsPerCollection
        );
        require(isCollectable, AgreementNotCollectable(_params.agreementId, reason));

        require(msg.sender == agreement.dataService, DataServiceNotAuthorized(_params.agreementId, msg.sender));

        // Check the service provider has an active provision with the data service
        // This prevents an attack where the payer can deny the service provider from collecting payments
        // by using a signer as data service to syphon off the tokens in the escrow to an account they control
        {
            uint256 tokensAvailable = _graphStaking().getProviderTokensAvailable(
                agreement.serviceProvider,
                agreement.dataService
            );
            require(0 < tokensAvailable, UnauthorizedDataService(agreement.dataService));
        }

        // Always validate temporal constraints (min/maxSecondsPerCollection) even for
        // zero-token collections, to prevent bypassing temporal windows while updating
        // lastCollectionAt.
        uint256 tokensToCollect = _requireValidCollect(
            agreement,
            _params.agreementId,
            _params.tokens,
            collectionSeconds
        );

        if (_params.tokens != 0) {
            uint256 slippage = _params.tokens - tokensToCollect;
            /* solhint-disable gas-strict-inequalities */
            require(
                slippage <= _params.maxSlippage,
                ExcessiveSlippage(_params.tokens, tokensToCollect, _params.maxSlippage)
            );
            /* solhint-enable gas-strict-inequalities */
        }
        agreement.lastCollectionAt = uint64(block.timestamp);

        // Eligibility gate: only when the agreement has CONDITION_ELIGIBILITY_CHECK set.
        // Fails open: collection proceeds if the staticcall reverts or returns malformed data.
        // Only an explicit isEligible() == 0 blocks collection. This prevents a buggy payer
        // callback from griefing the service provider.
        // Low-level staticcall avoids caller-side ABI decoding reverts (skipped if payer is caller).
        if (
            0 < tokensToCollect &&
            (agreement.activeTerms.conditions & CONDITION_ELIGIBILITY_CHECK != 0) &&
            _shouldCallback(agreement.payer)
        ) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = agreement.payer.staticcall{ gas: MAX_CALLBACK_GAS }(
                abi.encodeCall(IProviderEligibility.isEligible, (agreement.serviceProvider))
            );
            if (success && !(result.length < 32) && abi.decode(result, (uint256)) == 0)
                revert CollectionNotEligible(_params.agreementId, agreement.serviceProvider);

            if (!success || result.length < 32)
                emit PayerCallbackFailed(_params.agreementId, agreement.payer, PayerCallbackStage.EligibilityCheck);
        }

        // Let contract payers top up escrow if short
        if (0 < tokensToCollect && _shouldCallback(agreement.payer)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok, ) = agreement.payer.call{ gas: MAX_CALLBACK_GAS }(
                abi.encodeCall(IAgreementOwner.beforeCollection, (_params.agreementId, tokensToCollect))
            );
            if (!ok) {
                emit PayerCallbackFailed(_params.agreementId, agreement.payer, PayerCallbackStage.BeforeCollection);
            }
        }

        if (0 < tokensToCollect) {
            _graphPaymentsEscrow().collect(
                _paymentType,
                agreement.payer,
                agreement.serviceProvider,
                tokensToCollect,
                agreement.dataService,
                _params.dataServiceCut,
                _params.receiverDestination
            );
        }

        emit RCACollected(_params.agreementId, _params.collectionId, agreement.state);

        // Notify contract payers so they can reconcile escrow in the same transaction.
        if (_shouldCallback(agreement.payer)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok, ) = agreement.payer.call{ gas: MAX_CALLBACK_GAS }(
                abi.encodeCall(IAgreementOwner.afterCollection, (_params.agreementId, tokensToCollect))
            );
            if (!ok) {
                emit PayerCallbackFailed(_params.agreementId, agreement.payer, PayerCallbackStage.AfterCollection);
            }
        }

        if (agreement.state & SETTLED == 0 && _getMaxNextClaim(_params.agreementId, CLAIM_SCOPE_ACTIVE) == 0)
            agreement.state = agreement.state | SETTLED;

        // Auto-update: promote pending terms when the current cycle settles.
        // On success _accept emits the ACCEPTED notification, so skip the SETTLED one.
        bool autoUpdated;
        if (
            (agreement.state & (SETTLED | AUTO_UPDATE) == (SETTLED | AUTO_UPDATE)) && agreement.pendingTerms.endsAt != 0
        ) autoUpdated = _tryAutoUpdate(_params.agreementId, agreement);
        if (agreement.state & SETTLED != 0 && !autoUpdated) {
            _emitAndNotify(
                _params.agreementId,
                agreement.activeTerms.hash,
                agreement.state,
                agreement.dataService,
                agreement.payer
            );
        }

        return tokensToCollect;
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Accept terms (initial or update). Returns false only when catchCallbackRevert is true
     * and the data service callback reverts; otherwise always returns true or reverts.
     * @param agreementId The agreement ID
     * @param versionHash The expected terms hash
     * @param extraData Opaque data forwarded to the data service callback
     * @param agreement The agreement storage reference
     * @param terms The terms to accept (activeTerms or pendingTerms)
     * @param skipDeadlineCheck True to skip the offer deadline check
     * @param catchCallbackRevert True to catch data service callback reverts (for auto-update)
     * @param options Bitmask of agreement options (e.g. AUTO_UPDATE) to apply to state
     * @return True if accept succeeded, false if callback reverted and catchCallbackRevert was true
     */
    /* solhint-disable function-max-lines */
    function _accept(
        bytes16 agreementId,
        bytes32 versionHash,
        bytes memory extraData,
        AgreementStorage storage agreement,
        AgreementTerms storage terms,
        bool skipDeadlineCheck,
        bool catchCallbackRevert,
        uint16 options
    ) private returns (bool) {
        require(terms.hash != bytes32(0), AgreementTermsEmpty(agreementId));
        require(versionHash == terms.hash, AgreementHashMismatch(agreementId, terms.hash, versionHash));

        // Enforce offer deadline (skipped for auto-update where expiry is the trigger).
        // deadline=0 means "no deadline" — used by WITH_NOTICE updates where the payer
        // does not set an explicit acceptance deadline.
        if (!skipDeadlineCheck && terms.deadline != 0) {
            // solhint-disable-next-line gas-strict-inequalities
            require(block.timestamp <= terms.deadline, AgreementDeadlineElapsed(block.timestamp, terms.deadline));
        }

        // Re-validate time-dependent constraints for the new terms.
        // Skipped for auto-update: terms were validated at offer time and invariants can't change.
        if (!catchCallbackRevert) {
            _requireValidCollectionWindowParams(
                terms.endsAt,
                terms.minSecondsPerCollection,
                terms.maxSecondsPerCollection
            );
        }

        // Data service callback — validates and sets up domain-specific state.
        // Skip for no-op updates: when extraData is empty, metadata is unchanged, and the
        // agreement is not SETTLED. SETTLED transitions always notify (revival path).
        // Safe because data service callbacks only depend on metadata and extraData, not on
        // collector-level pricing fields (maxInitialTokens, maxOngoingTokensPerSecond, etc.).
        {
            bool skipCallback = agreement.pendingTerms.hash == versionHash &&
                extraData.length == 0 &&
                keccak256(terms.metadata) == keccak256(agreement.activeTerms.metadata) &&
                (agreement.state & SETTLED == 0);

            if (!skipCallback) {
                if (catchCallbackRevert) {
                    // solhint-disable-next-line avoid-low-level-calls
                    (bool ok, ) = agreement.dataService.call{ gas: MAX_CALLBACK_GAS }(
                        abi.encodeCall(
                            IDataServiceAgreements.acceptAgreement,
                            (
                                agreementId,
                                versionHash,
                                agreement.payer,
                                agreement.serviceProvider,
                                terms.metadata,
                                extraData
                            )
                        )
                    );
                    if (!ok) return false;
                } else {
                    IDataServiceAgreements(agreement.dataService).acceptAgreement(
                        agreementId,
                        versionHash,
                        agreement.payer,
                        agreement.serviceProvider,
                        terms.metadata,
                        extraData
                    );
                }
            }
        }

        agreement.acceptedAt = uint64(block.timestamp);
        uint16 oldState = agreement.state;

        // For updates: promote pending terms to active, clear notice state, revive agreement
        if (agreement.pendingTerms.hash == versionHash) {
            agreement.activeTerms = agreement.pendingTerms;
            agreement.activeOfferNonce = agreement.pendingOfferNonce;
            delete agreement.pendingTerms;
            agreement.pendingOfferNonce = 0;
            // Clear all clearable flags, keep REGISTERED | ACCEPTED | UPDATE
            uint16 clearMask = NOTICE_GIVEN | SETTLED | BY_PAYER | BY_PROVIDER | BY_DATA_SERVICE | AUTO_UPDATED;
            oldState = (oldState & ~clearMask) | UPDATE;
        }

        // Set collectableUntil to the (now-active) terms endsAt — covers both initial and update accepts
        agreement.collectableUntil = agreement.activeTerms.endsAt;

        uint16 newState = oldState | ACCEPTED;
        // Apply togglable options (currently only AUTO_UPDATE)
        newState = (newState & ~AUTO_UPDATE) | (options & AUTO_UPDATE);
        agreement.state = newState;

        _emitAndNotify(agreementId, versionHash, newState, agreement.dataService, agreement.payer);
        return true;
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Validate and store an RCA offer. Does not activate — data service must call accept().
     * @param _rca The RCA to validate and store
     * @return agreementId The generated agreement ID
     */
    /* solhint-disable function-max-lines */
    function _validateAndStoreOffer(RecurringCollectionAgreement memory _rca) private returns (bytes16, bytes32) {
        /* solhint-disable gas-strict-inequalities */
        require(block.timestamp <= _rca.deadline, AgreementDeadlineElapsed(block.timestamp, _rca.deadline));
        /* solhint-enable gas-strict-inequalities */

        bytes16 agreementId = _generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );

        require(agreementId != bytes16(0), AgreementIdZero());
        require(
            _rca.dataService != address(0) && _rca.payer != address(0) && _rca.serviceProvider != address(0),
            AgreementAddressNotSet()
        );
        _requireValidCollectionWindowParams(_rca.endsAt, _rca.minSecondsPerCollection, _rca.maxSecondsPerCollection);
        _requireEligibilityCapability(_rca.payer, _rca.conditions);

        // Reverts on overflow — rejecting terms that could prevent collection
        _rca.maxOngoingTokensPerSecond * _rca.maxSecondsPerCollection;

        AgreementStorage storage agreement = _getAgreementStorage(agreementId);
        require(agreement.state == 0, AgreementIncorrectState(agreementId, agreement.state));

        agreement.state = REGISTERED;
        agreement.dataService = _rca.dataService;
        agreement.payer = _rca.payer;
        agreement.serviceProvider = _rca.serviceProvider;
        agreement.activeTerms.deadline = _rca.deadline;
        agreement.activeTerms.endsAt = _rca.endsAt;
        agreement.activeTerms.maxInitialTokens = _rca.maxInitialTokens;
        agreement.activeTerms.maxOngoingTokensPerSecond = _rca.maxOngoingTokensPerSecond;
        agreement.activeTerms.minSecondsPerCollection = _rca.minSecondsPerCollection;
        agreement.activeTerms.maxSecondsPerCollection = _rca.maxSecondsPerCollection;
        agreement.activeTerms.conditions = _rca.conditions;
        agreement.activeTerms.minSecondsPayerCancellationNotice = _rca.minSecondsPayerCancellationNotice;
        agreement.updateNonce = 0;
        agreement.activeOfferNonce = _rca.nonce;
        agreement.activeTerms.hash = hashRCA(_rca);
        agreement.activeTerms.metadata = _rca.metadata;

        _emitAndNotify(agreementId, agreement.activeTerms.hash, REGISTERED, _rca.dataService, _rca.payer);

        return (agreementId, agreement.activeTerms.hash);
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice State-driven update storage. Validates nonce, stores terms, emits event.
     * @dev If Offered: overwrites activeTerms (revises the offer).
     *      If Accepted: writes to pendingTerms (stages for acceptUpdate).
     *      Otherwise: reverts.
     * @param agreement The storage reference to the agreement data
     * @param rcau The Recurring Collection Agreement Update to apply
     * @param offerOptions Bitmask of offer options (e.g. WITH_NOTICE) controlling update behavior
     * @return The offer result containing the agreement ID and updated terms
     */
    /* solhint-disable function-max-lines */
    function _validateAndStoreUpdate(
        AgreementStorage storage agreement,
        RecurringCollectionAgreementUpdate memory rcau,
        uint16 offerOptions
    ) private returns (OfferResult memory) {
        uint16 state = agreement.state;

        require(state & REGISTERED != 0, AgreementIncorrectState(rcau.agreementId, state));

        if (offerOptions & IF_NOT_ACCEPTED != 0)
            require(state & ACCEPTED == 0, AgreementIncorrectState(rcau.agreementId, state));

        if (offerOptions & WITH_NOTICE == 0 || rcau.deadline != 0)
            // solhint-disable-next-line gas-strict-inequalities
            require(rcau.deadline >= block.timestamp, AgreementDeadlineElapsed(block.timestamp, rcau.deadline));

        uint32 expectedNonce = agreement.updateNonce + 1;
        require(rcau.nonce == expectedNonce, InvalidUpdateNonce(rcau.agreementId, expectedNonce, rcau.nonce));
        agreement.updateNonce = expectedNonce;

        _requireValidCollectionWindowParams(rcau.endsAt, rcau.minSecondsPerCollection, rcau.maxSecondsPerCollection);
        _requireEligibilityCapability(agreement.payer, rcau.conditions);

        // Reverts on overflow — rejecting terms that could prevent collection
        rcau.maxOngoingTokensPerSecond * rcau.maxSecondsPerCollection;

        AgreementTerms memory terms;
        terms.deadline = rcau.deadline;
        terms.endsAt = rcau.endsAt;
        terms.maxInitialTokens = rcau.maxInitialTokens;
        terms.maxOngoingTokensPerSecond = rcau.maxOngoingTokensPerSecond;
        terms.minSecondsPerCollection = rcau.minSecondsPerCollection;
        terms.maxSecondsPerCollection = rcau.maxSecondsPerCollection;
        terms.conditions = rcau.conditions;
        terms.minSecondsPayerCancellationNotice = rcau.minSecondsPayerCancellationNotice;
        terms.hash = hashRCAU(rcau);
        terms.metadata = rcau.metadata;

        uint16 eventState;
        if (state & ACCEPTED == 0) {
            // Not yet accepted — overwrite active terms directly
            agreement.activeTerms = terms;
            agreement.activeOfferNonce = rcau.nonce;
            state = state | UPDATE;
            agreement.state = state;
            eventState = state;
        } else {
            // Already accepted — store as pending
            agreement.pendingTerms = terms;
            agreement.pendingOfferNonce = rcau.nonce;
            eventState = state | UPDATE; // UPDATE in event indicates this version is from an update

            // WITH_NOTICE: derive notice cutoff from rcau.deadline or agreement state
            if (offerOptions & WITH_NOTICE != 0) {
                uint64 noticeCutoff = rcau.deadline != 0
                    ? rcau.deadline
                    : uint64(block.timestamp) + agreement.activeTerms.minSecondsPayerCancellationNotice;
                _applyNotice(agreement, rcau.agreementId, noticeCutoff);
                state = state | NOTICE_GIVEN | BY_PAYER;
                agreement.state = state;
                eventState = state | UPDATE;
            }
        }

        _emitAndNotify(rcau.agreementId, terms.hash, eventState, agreement.dataService, agreement.payer);

        return
            OfferResult({
                agreementId: rcau.agreementId,
                dataService: agreement.dataService,
                serviceProvider: agreement.serviceProvider,
                versionHash: terms.hash,
                state: eventState
            });
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Attempt to auto-update an agreement by promoting pending terms.
     * @dev Called from _collect() when collection window is exhausted and AUTO_UPDATE is set.
     * Uses non-reverting callback so collect always succeeds even if upgrade fails.
     * @param agreementId The agreement ID
     * @param agreement The agreement storage reference
     * @return updated True if upgrade succeeded
     */
    function _tryAutoUpdate(bytes16 agreementId, AgreementStorage storage agreement) private returns (bool updated) {
        // Reuse _accept with catchCallbackRevert=true, skipDeadlineCheck=true.
        // Collection window validation is skipped — terms were validated at offer time.
        // Pass current state as options to preserve AUTO_UPDATE bit.
        updated = _accept(
            agreementId,
            agreement.pendingTerms.hash,
            "",
            agreement,
            agreement.pendingTerms,
            true,
            true,
            agreement.state
        );

        if (updated) agreement.state = agreement.state | AUTO_UPDATED;

        emit AutoUpdateAttempted(agreementId, updated);
    }

    /**
     * @notice Apply a notice cutoff to an agreement, enforcing minSecondsPayerCancellationNotice.
     * @dev Active terms are not modified — collectableUntil is reduced to min(collectableUntil, noticeCutoff).
     * @param agreement The agreement storage reference
     * @param agreementId The agreement ID (for error reporting)
     * @param noticeCutoff The target cutoff timestamp (must satisfy min notice from now)
     */
    function _applyNotice(AgreementStorage storage agreement, bytes16 agreementId, uint64 noticeCutoff) private {
        uint32 minNotice = agreement.activeTerms.minSecondsPayerCancellationNotice;
        uint256 actualNotice = noticeCutoff < block.timestamp ? 0 : noticeCutoff - block.timestamp;
        /* solhint-disable gas-strict-inequalities */
        require(minNotice <= actualNotice, InsufficientNotice(agreementId, minNotice, actualNotice));
        /* solhint-enable gas-strict-inequalities */

        if (noticeCutoff < agreement.collectableUntil) agreement.collectableUntil = noticeCutoff;
    }

    /**
     * @notice Emit {AgreementUpdated} and send non-reverting lifecycle notifications to both
     * the data service and the payer.
     * @dev Consolidates the emit-and-notify pattern used by every state-transition path.
     * Notifications to `msg.sender` and EOAs are skipped by {_notifyStateChange}.
     * @param _agreementId The agreement ID
     * @param _versionHash The EIP-712 hash of the terms involved in this change
     * @param _state The agreement state flags
     * @param _dataService The data service to notify
     * @param _payer The payer to notify
     */
    function _emitAndNotify(
        bytes16 _agreementId,
        bytes32 _versionHash,
        uint16 _state,
        address _dataService,
        address _payer
    ) private {
        emit AgreementUpdated(_agreementId, _versionHash, _state);
        _notifyStateChange(_dataService, _agreementId, _versionHash, _state);
        _notifyStateChange(_payer, _agreementId, _versionHash, _state);
    }

    /**
     * @notice Non-reverting callback to notify a contract of an agreement state change.
     * @dev Uses low-level call with gas cap. Failures are silently ignored.
     *
     * Skips notification when `_target` is `msg.sender` (caller already has execution
     * context) or an EOA (no code to call). This eliminates callback loops, simplifies
     * reentrancy reasoning, and removes an attack surface — callers sequence their own
     * post-call reconciliation instead of relying on a callback from the callee.
     *
     * @param _target The contract to notify
     * @param _agreementId The agreement ID
     * @param _versionHash The EIP-712 hash of the terms involved in this change
     * @param _state The agreement state flags, includes UPDATE when applicable
     */
    function _notifyStateChange(address _target, bytes16 _agreementId, bytes32 _versionHash, uint16 _state) private {
        if (_target == msg.sender || _target.code.length == 0) return;
        (
            // solhint-disable-next-line avoid-low-level-calls
            _target.call{ gas: MAX_CALLBACK_GAS }(
                abi.encodeCall(
                    IAgreementStateChangeCallback.afterAgreementStateChange,
                    (_agreementId, _versionHash, _state)
                )
            )
        );
    }

    // -- Private view/pure --

    function _getStorage() private pure returns (RecurringCollectorStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := RECURRING_COLLECTOR_STORAGE_LOCATION
        }
    }

    /**
     * @notice Check whether a callback to `_target` should proceed.
     * @dev Returns false (skip) when the target is `msg.sender` (caller sequences its own
     * post-call logic) or an EOA (no code to call). Reverts if gas is insufficient for a
     * safe callback dispatch.
     * @param _target The intended callback recipient
     * @return True if the callback should be dispatched
     */
    function _shouldCallback(address _target) private view returns (bool) {
        if (_target == msg.sender || _target.code.length == 0) return false;
        if (gasleft() < (MAX_CALLBACK_GAS * 64) / 63) revert InsufficientCallbackGas();
        return true;
    }

    /**
     * @notice Gets an agreement to be updated.
     * @param _agreementId The ID of the agreement to get
     * @return The storage reference to the agreement data
     */
    function _getAgreementStorage(bytes16 _agreementId) private view returns (AgreementStorage storage) {
        return _getStorage().agreements[_agreementId];
    }

    function _getCollectionInfo(
        uint16 _state,
        uint64 _collectableUntil,
        uint64 _lastCollectionAt,
        uint64 _acceptedAt,
        uint32 _maxSecondsPerCollection
    ) private view returns (bool, uint256, AgreementNotCollectableReason) {
        // Collectable = accepted and not settled
        bool hasValidState = (_state & (ACCEPTED | SETTLED)) == ACCEPTED;

        if (!hasValidState) {
            return (false, 0, AgreementNotCollectableReason.InvalidAgreementState);
        }

        uint256 collectionEnd = block.timestamp < _collectableUntil ? block.timestamp : _collectableUntil;
        uint256 collectionStart = 0 < _lastCollectionAt ? _lastCollectionAt : _acceptedAt;

        if (collectionEnd < collectionStart) {
            return (false, 0, AgreementNotCollectableReason.InvalidTemporalWindow);
        }

        if (collectionStart == collectionEnd) {
            return (false, 0, AgreementNotCollectableReason.ZeroCollectionSeconds);
        }

        uint256 elapsed = collectionEnd - collectionStart;
        return (true, Math.min(elapsed, uint256(_maxSecondsPerCollection)), AgreementNotCollectableReason.None);
    }

    /**
     * @notice Validates temporal constraints and caps the requested token amount.
     * @dev Enforces `minSecondsPerCollection` (unless canceled/elapsed) and returns the lesser of
     * the requested amount and the RCA payer's per-collection cap
     * (`maxOngoingTokensPerSecond * collectionSeconds`, plus `maxInitialTokens` on first collection).
     * @param _agreement The agreement data
     * @param _agreementId The ID of the agreement
     * @param _tokens The requested token amount (upper bound from data service)
     * @param _collectionSeconds Collection duration, already capped at maxSecondsPerCollection
     * @return The capped token amount: min(_tokens, payer's max for this collection)
     */
    function _requireValidCollect(
        AgreementStorage storage _agreement,
        bytes16 _agreementId,
        uint256 _tokens,
        uint256 _collectionSeconds
    ) private view returns (uint256) {
        if (block.timestamp < _agreement.collectableUntil) {
            require(
                // solhint-disable-next-line gas-strict-inequalities
                _collectionSeconds >= _agreement.activeTerms.minSecondsPerCollection,
                CollectionTooSoon(
                    _agreementId,
                    // casting to uint32 is safe because _collectionSeconds < minSecondsPerCollection (uint32)
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32(_collectionSeconds),
                    _agreement.activeTerms.minSecondsPerCollection
                )
            );
        }
        // _collectionSeconds is already capped at maxSecondsPerCollection by _getCollectionInfo
        uint256 maxTokens = _agreement.activeTerms.maxOngoingTokensPerSecond * _collectionSeconds;
        maxTokens += _agreement.lastCollectionAt == 0 ? _agreement.activeTerms.maxInitialTokens : 0;

        return Math.min(_tokens, maxTokens);
    }

    /**
     * @notice Requires that the collection window parameters are valid.
     * @param _endsAt The end time of the agreement
     * @param _minSecondsPerCollection The minimum seconds per collection
     * @param _maxSecondsPerCollection The maximum seconds per collection
     */
    function _requireValidCollectionWindowParams(
        uint64 _endsAt,
        uint32 _minSecondsPerCollection,
        uint32 _maxSecondsPerCollection
    ) private view {
        InvalidCollectionWindowReason reason;
        /* solhint-disable gas-strict-inequalities */
        if (_endsAt <= block.timestamp) reason = InvalidCollectionWindowReason.ElapsedEndsAt;
        else if (
            _maxSecondsPerCollection <= _minSecondsPerCollection ||
            _maxSecondsPerCollection - _minSecondsPerCollection < MIN_SECONDS_COLLECTION_WINDOW
        )
            reason = InvalidCollectionWindowReason.InvalidWindow;
            /* solhint-enable gas-strict-inequalities */
        else if (_endsAt - block.timestamp < uint256(_minSecondsPerCollection) + MIN_SECONDS_COLLECTION_WINDOW)
            reason = InvalidCollectionWindowReason.InsufficientDuration;
        else return;

        revert AgreementInvalidCollectionWindow(reason, _minSecondsPerCollection, _maxSecondsPerCollection);
    }

    /**
     * @notice Validates that a payer for an agreement with CONDITION_ELIGIBILITY_CHECK
     * implements IProviderEligibility (via ERC-165).
     * @dev Agreeing to eligibility checks is a significant commitment — it gives the payer
     * the ability to deny payment to the service provider. Both parties must see this
     * condition explicitly at offer time so neither is surprised.
     *
     * Without this check a payer could include an apparently-inert eligibility condition
     * (e.g. from an EOA or contract that does not yet implement the interface) that later
     * becomes enforceable via account upgrade (ERC-7702, metamorphic deploy, etc.),
     * enabling surprise payment denials. Requiring ERC-165 confirmation at offer time
     * ensures the condition is real and intentional.
     *
     * Note: even if a payer contract supports IProviderEligibility, it is free to create
     * offers without CONDITION_ELIGIBILITY_CHECK — the condition is opt-in per agreement.
     * @param _payer The payer address to check for eligibility capability
     * @param _conditions The condition flags bitmap
     */
    function _requireEligibilityCapability(address _payer, uint16 _conditions) private view {
        if (_conditions & CONDITION_ELIGIBILITY_CHECK != 0) {
            require(
                ERC165Checker.supportsInterface(_payer, type(IProviderEligibility).interfaceId),
                EligibilityConditionNotSupported(_payer)
            );
        }
    }

    function _getMaxNextClaim(bytes16 agreementId, uint8 claimScope) private view returns (uint256 maxClaim) {
        AgreementStorage memory _a = _getStorage().agreements[agreementId];

        uint256 maxCurrentClaim = claimScope & CLAIM_SCOPE_ACTIVE != 0 ? _maxClaimForTerms(_a, _a.activeTerms) : 0;
        uint256 maxPendingClaim = claimScope & CLAIM_SCOPE_PENDING != 0 ? _maxClaimForTerms(_a, _a.pendingTerms) : 0;

        maxClaim = maxCurrentClaim < maxPendingClaim ? maxPendingClaim : maxCurrentClaim;
    }

    /**
     * @notice Compute max claim for a given set of terms against the agreement's lifecycle state.
     * @dev Handles all agreement states uniformly:
     *   - NotAccepted with stored terms (offered): block.timestamp as proxy for acceptedAt
     *   - Accepted: lastCollectionAt/acceptedAt-based window up to endsAt
     *   - CanceledByPayer / CanceledByServiceProvider: window capped at min(collectableUntil, endsAt)
     *   - Settled / empty slots: 0
     * @param _a The agreement data (lifecycle state)
     * @param _terms The terms to evaluate (activeTerms or pendingTerms)
     * @return The maximum possible claim for the given terms
     */
    function _maxClaimForTerms(
        AgreementStorage memory _a,
        AgreementTerms memory _terms
    ) private view returns (uint256) {
        if (_terms.endsAt == 0) return 0;

        uint256 collectionStart;
        uint256 collectionEnd;

        uint16 s = _a.state;
        if (s & SETTLED != 0 || s == 0) {
            // Settled or empty — nothing claimable
            return 0;
        } else if (s & ACCEPTED == 0) {
            // Registered but not accepted (offered) — use block.timestamp as proxy for acceptedAt
            collectionStart = block.timestamp;
            collectionEnd = _terms.endsAt;
        } else if (s & NOTICE_GIVEN == 0) {
            // Active (accepted, not terminated)
            collectionStart = 0 < _a.lastCollectionAt ? _a.lastCollectionAt : _a.acceptedAt;
            collectionEnd = _terms.endsAt;
        } else {
            // Terminated but not settled — collect up to min(collectableUntil, terms.endsAt)
            collectionStart = 0 < _a.lastCollectionAt ? _a.lastCollectionAt : _a.acceptedAt;
            collectionEnd = _a.collectableUntil < _terms.endsAt ? _a.collectableUntil : _terms.endsAt;
        }

        if (!(collectionStart < collectionEnd)) return 0;
        uint256 windowSeconds = collectionEnd - collectionStart;
        uint256 effectiveSeconds = windowSeconds < _terms.maxSecondsPerCollection
            ? windowSeconds
            : _terms.maxSecondsPerCollection;
        return
            _terms.maxOngoingTokensPerSecond * effectiveSeconds +
            (_a.lastCollectionAt == 0 ? _terms.maxInitialTokens : 0);
    }

    /**
     * @notice Internal function to generate deterministic agreement ID
     * @param _payer The address of the payer
     * @param _dataService The address of the data service
     * @param _serviceProvider The address of the service provider
     * @param _deadline The deadline for accepting the agreement
     * @param _nonce A unique nonce for preventing collisions
     * @return agreementId The deterministically generated agreement ID
     */
    function _generateAgreementId(
        address _payer,
        address _dataService,
        address _serviceProvider,
        uint64 _deadline,
        uint256 _nonce
    ) private pure returns (bytes16) {
        return bytes16(keccak256(abi.encode(_payer, _dataService, _serviceProvider, _deadline, _nonce)));
    }
}
