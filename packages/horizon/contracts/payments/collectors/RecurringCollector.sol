// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

// solhint-disable gas-strict-inequalities

import { EIP712Upgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
// solhint-disable-next-line no-unused-import
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol"; // for @inheritdoc
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import {
    IAgreementCollector,
    OFFER_TYPE_NONE,
    OFFER_TYPE_NEW,
    OFFER_TYPE_UPDATE,
    ACCEPTED,
    REGISTERED,
    NOTICE_GIVEN,
    SETTLED,
    BY_PAYER,
    BY_PROVIDER,
    UPDATE,
    SCOPE_ACTIVE,
    SCOPE_PENDING,
    SCOPE_SIGNED,
    VERSION_CURRENT,
    VERSION_NEXT
} from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { IDataServiceAgreements } from "@graphprotocol/interfaces/contracts/data-service/IDataServiceAgreements.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

/**
 * @title RecurringCollector contract
 * @author Edge & Node
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCA (Recurring Collection Agreement).
 *
 * @custom:security Self-authorization: RC overrides {_isAuthorized} to return true whenever
 * `signer == address(this)`, so RC itself must perform the appropriate authorization check
 * before any external call.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is
    Initializable,
    EIP712Upgradeable,
    GraphDirectory,
    Authorizable,
    PausableUpgradeable,
    IRecurringCollector
{
    using PPMMath for uint256;

    /// @notice The minimum number of seconds that must be between two collections
    uint32 public constant MIN_SECONDS_COLLECTION_WINDOW = 600;

    /// @notice Condition flag: agreement requires eligibility checks before collection
    uint16 public constant CONDITION_ELIGIBILITY_CHECK = 1;

    /// @notice Maximum gas forwarded to payer contract callbacks (beforeCollection / afterCollection).
    /// Caps gas available to payer implementations, preventing 63/64-rule gas siphoning attacks
    /// that could starve the core collect() call of gas.
    uint256 private constant MAX_PAYER_CALLBACK_GAS = 1_500_000;

    /// @notice Gas overhead between the gasleft() precheck and the actual CALL/STATICCALL opcode.
    /// Covers ABI encoding, stack/memory setup, and the CALL base cost so that at least
    /// MAX_PAYER_CALLBACK_GAS is forwarded to the callee. Sized to cover the cold-account
    /// EIP-2929 access cost (2_600) plus Solidity framing.
    uint256 private constant CALLBACK_GAS_OVERHEAD = 3_000;

    /* solhint-disable gas-small-strings */
    /// @notice The EIP712 typehash for the RecurringCollectionAgreement struct
    bytes32 public constant EIP712_RCA_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreement(uint64 deadline,uint64 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint256 nonce,bytes metadata)"
        );

    /// @notice The EIP712 typehash for the RecurringCollectionAgreementUpdate struct
    bytes32 public constant EIP712_RCAU_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint16 conditions,uint32 nonce,bytes metadata)"
        );
    /* solhint-enable gas-small-strings */

    /// @notice A stored offer (RCA or RCAU) with its EIP-712 hash
    struct StoredOffer {
        bytes32 offerHash;
        bytes data;
    }

    /// @custom:storage-location erc7201:graphprotocol.storage.RecurringCollector
    struct RecurringCollectorStorage {
        /// @notice List of pause guardians and their allowed status
        mapping(address pauseGuardian => bool allowed) pauseGuardians;
        /// @notice Tracks agreements
        mapping(bytes16 agreementId => AgreementData data) agreements;
        /// @notice Stored RCA offers (pre-approval), keyed by agreement ID
        mapping(bytes16 agreementId => StoredOffer offer) rcaOffers;
        /// @notice Stored RCAU offers (pre-approval), keyed by agreement ID
        mapping(bytes16 agreementId => StoredOffer offer) rcauOffers;
        /// @notice Cancelled offer hashes, keyed by signer then EIP-712 hash.
        /// Stores the agreementId that is blocked; bytes16(0) means not cancelled.
        mapping(address signer => mapping(bytes32 hash => bytes16 agreementId)) cancelledOffers;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("graphprotocol.storage.RecurringCollector")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RECURRING_COLLECTOR_STORAGE_LOCATION =
        0x436d179d846767cf46c6cda3ec5a404bcbe1b4351ce320082402e5e9ab4d6600;

    function _getStorage() private pure returns (RecurringCollectorStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := RECURRING_COLLECTOR_STORAGE_LOCATION
        }
    }

    /**
     * @notice List of pause guardians and their allowed status
     * @param pauseGuardian The address to check
     * @return Whether the address is a pause guardian
     */
    function pauseGuardians(address pauseGuardian) public view override returns (bool) {
        return _getStorage().pauseGuardians[pauseGuardian];
    }

    /**
     * @notice Checks if the caller is a pause guardian.
     */
    modifier onlyPauseGuardian() {
        _checkPauseGuardian();
        _;
    }

    function _checkPauseGuardian() internal view {
        require(_getStorage().pauseGuardians[msg.sender], RecurringCollectorNotPauseGuardian(msg.sender));
    }

    /**
     * @notice Constructs a new instance of the RecurringCollector implementation contract.
     * @dev Immutables are set here; proxy state is initialized via {initialize}.
     * @param controller The address of the Graph controller.
     * @param revokeSignerThawingPeriod The duration (in seconds) in which a signer is thawing before they can be revoked.
     */
    constructor(
        address controller,
        uint256 revokeSignerThawingPeriod
    ) GraphDirectory(controller) Authorizable(revokeSignerThawingPeriod) {
        _disableInitializers();
    }

    /* solhint-disable gas-calldata-parameters */
    /**
     * @notice Initializes the contract (proxy storage).
     * @param eip712Name The name of the EIP712 domain.
     * @param eip712Version The version of the EIP712 domain.
     */
    function initialize(string memory eip712Name, string memory eip712Version) external initializer {
        __EIP712_init(eip712Name, eip712Version);
        __Pausable_init();
    }
    /* solhint-enable gas-calldata-parameters */

    /// @inheritdoc IRecurringCollector
    function pause() external override onlyPauseGuardian {
        _pause();
    }

    /// @inheritdoc IRecurringCollector
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
        require(msg.sender == _graphController().getGovernor(), RecurringCollectorNotGovernor(msg.sender));
        RecurringCollectorStorage storage $ = _getStorage();
        require(
            $.pauseGuardians[_pauseGuardian] != _allowed,
            RecurringCollectorPauseGuardianNoChange(_pauseGuardian, _allowed)
        );
        $.pauseGuardians[_pauseGuardian] = _allowed;
        emit PauseGuardianSet(_pauseGuardian, _allowed);
    }

    /**
     * @inheritdoc IPaymentsCollector
     * @notice Initiate a payment collection through the payments protocol.
     * See {IPaymentsCollector.collect}.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data
    ) external whenNotPaused returns (uint256) {
        try this.decodeCollectData(data) returns (CollectParams memory collectParams) {
            return _collect(paymentType, collectParams);
        } catch {
            revert RecurringCollectorInvalidCollectData(data);
        }
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Accept a Recurring Collection Agreement.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function accept(
        RecurringCollectionAgreement calldata rca,
        bytes calldata signature
    ) external whenNotPaused returns (bytes16 agreementId) {
        bytes32 rcaHash;
        (agreementId, rcaHash) = _rcaIdAndHash(rca);

        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        // Idempotent: already accepted with the same hash → no-op (skip deadline + auth).
        if (agreement.state == AgreementState.Accepted && agreement.activeTermsHash == rcaHash) return agreementId;

        require(
            block.timestamp <= rca.deadline,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rca.deadline)
        );

        _requireAuthorization(rca.payer, rcaHash, signature, agreementId, OFFER_TYPE_NEW);

        if ($.rcaOffers[agreementId].offerHash != rcaHash) {
            $.rcaOffers[agreementId] = StoredOffer({ offerHash: rcaHash, data: abi.encode(rca) });
            emit OfferStored(agreementId, rca.payer, OFFER_TYPE_NEW, rcaHash);
        }

        _validateAndStoreAgreement(rca, agreementId, rcaHash);

        agreement.acceptedAt = uint64(block.timestamp);
        agreement.state = AgreementState.Accepted;

        emit AgreementAccepted(
            rca.dataService,
            rca.payer,
            rca.serviceProvider,
            agreementId,
            rca.endsAt,
            rca.maxInitialTokens,
            rca.maxOngoingTokensPerSecond,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );
    }

    /**
     * @notice Validates RCA fields and registers the agreement (identity + terms).
     * Does not flip state to Accepted — caller handles the accept step.
     * @param _rca The Recurring Collection Agreement to validate and store
     * @param agreementId The deterministic agreement ID
     * @param _rcaHash The EIP-712 hash of the RCA
     */
    function _validateAndStoreAgreement(
        RecurringCollectionAgreement memory _rca,
        bytes16 agreementId,
        bytes32 _rcaHash
    ) private {
        require(msg.sender == _rca.dataService, RecurringCollectorUnauthorizedCaller(msg.sender, _rca.dataService));

        require(
            _rca.dataService != address(0) && _rca.payer != address(0) && _rca.serviceProvider != address(0),
            RecurringCollectorAgreementAddressNotSet()
        );

        AgreementData storage agreement = _getAgreementStorage(agreementId);
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );

        _requireValidTerms(
            _rca.deadline,
            _rca.endsAt,
            _rca.minSecondsPerCollection,
            _rca.maxSecondsPerCollection,
            _rca.payer,
            _rca.conditions,
            _rca.maxOngoingTokensPerSecond
        );

        agreement.dataService = _rca.dataService;
        agreement.payer = _rca.payer;
        agreement.serviceProvider = _rca.serviceProvider;
        agreement.endsAt = _rca.endsAt;
        agreement.maxInitialTokens = _rca.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = _rca.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = _rca.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = _rca.maxSecondsPerCollection;
        agreement.conditions = _rca.conditions;
        agreement.activeTermsHash = _rcaHash;
        agreement.updateNonce = 0;
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Cancel a Recurring Collection Agreement.
     * See {IRecurringCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external whenNotPaused {
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];
        require(
            agreement.state == AgreementState.Accepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );
        require(
            agreement.dataService == msg.sender,
            RecurringCollectorDataServiceNotAuthorized(agreementId, msg.sender)
        );
        agreement.canceledAt = uint64(block.timestamp);
        if (by == CancelAgreementBy.Payer) {
            agreement.state = AgreementState.CanceledByPayer;
        } else {
            agreement.state = AgreementState.CanceledByServiceProvider;
        }

        bytes32 pendingHash = $.rcauOffers[agreementId].offerHash;
        if (pendingHash != bytes32(0) && pendingHash != agreement.activeTermsHash) delete $.rcauOffers[agreementId];

        emit AgreementCanceled(agreement.dataService, agreement.payer, agreement.serviceProvider, agreementId, by);
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Update a Recurring Collection Agreement.
     * @dev Caller must be the data service for the agreement.
     * @dev Note: Updated pricing terms apply immediately and will affect the next collection
     * for the entire period since lastCollectionAt.
     */
    function update(RecurringCollectionAgreementUpdate calldata rcau, bytes calldata signature) external whenNotPaused {
        AgreementData storage agreement = _requireValidUpdateTarget(rcau.agreementId);

        bytes32 rcauHash = _hashRCAU(rcau);

        // Idempotent: already at this version (state is Accepted per _requireValidUpdateTarget).
        // Skip deadline + auth since no state change happens.
        if (agreement.activeTermsHash == rcauHash) return;

        require(
            block.timestamp <= rcau.deadline,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rcau.deadline)
        );

        _requireAuthorization(agreement.payer, rcauHash, signature, rcau.agreementId, OFFER_TYPE_UPDATE);

        uint32 expectedNonce = agreement.updateNonce + 1;
        require(
            rcau.nonce == expectedNonce,
            RecurringCollectorInvalidUpdateNonce(rcau.agreementId, expectedNonce, rcau.nonce)
        );

        RecurringCollectorStorage storage $ = _getStorage();
        if ($.rcauOffers[rcau.agreementId].offerHash != rcauHash) {
            $.rcauOffers[rcau.agreementId] = StoredOffer({ offerHash: rcauHash, data: abi.encode(rcau) });
            emit OfferStored(rcau.agreementId, agreement.payer, OFFER_TYPE_UPDATE, rcauHash);
        }

        _validateAndStoreUpdate(agreement, rcau, rcauHash);
        agreement.updateNonce = rcau.nonce;

        emit AgreementUpdated(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            rcau.agreementId,
            rcau.endsAt,
            rcau.maxInitialTokens,
            rcau.maxOngoingTokensPerSecond,
            rcau.minSecondsPerCollection,
            rcau.maxSecondsPerCollection
        );
    }

    /// @inheritdoc IRecurringCollector
    function recoverRCASigner(
        RecurringCollectionAgreement calldata rca,
        bytes calldata signature
    ) external view returns (address) {
        return _recoverRCASigner(rca, signature);
    }

    /// @inheritdoc IRecurringCollector
    function recoverRCAUSigner(
        RecurringCollectionAgreementUpdate calldata rcau,
        bytes calldata signature
    ) external view returns (address) {
        return _recoverRCAUSigner(rcau, signature);
    }

    /// @inheritdoc IRecurringCollector
    function hashRCA(RecurringCollectionAgreement calldata rca) external view returns (bytes32) {
        return _hashRCA(rca);
    }

    /// @inheritdoc IRecurringCollector
    function hashRCAU(RecurringCollectionAgreementUpdate calldata rcau) external view returns (bytes32) {
        return _hashRCAU(rcau);
    }

    /// @inheritdoc IRecurringCollector
    function getAgreement(bytes16 agreementId) external view returns (AgreementData memory) {
        return _getAgreement(agreementId);
    }

    /// @inheritdoc IRecurringCollector
    function getCollectionInfo(
        bytes16 agreementId
    ) external view returns (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason) {
        return _getCollectionInfo(_getAgreementStorage(agreementId));
    }

    /// @inheritdoc IAgreementCollector
    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getMaxNextClaimScoped(agreementId, 0);
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

    // -- IAgreementCollector --

    /// @inheritdoc IAgreementCollector
    function offer(
        uint8 offerType,
        bytes calldata data,
        uint16 /* options */
    ) external whenNotPaused returns (AgreementDetails memory details) {
        bytes16 agreementId;
        bytes32 versionHash;
        uint256 index;
        if (offerType == OFFER_TYPE_NEW) (agreementId, versionHash, index) = _offerNew(data);
        else if (offerType == OFFER_TYPE_UPDATE) (agreementId, versionHash, index) = _offerUpdate(data);
        else revert RecurringCollectorInvalidCollectData(data);

        details = _getAgreementDetails(agreementId, versionHash, index);
        require(msg.sender == details.payer, RecurringCollectorUnauthorizedCaller(msg.sender, details.payer));
    }

    /**
     * @notice Process a new offer (OFFER_TYPE_NEW).
     * @param _data The ABI-encoded RecurringCollectionAgreement
     * @return agreementId The deterministic agreement ID
     * @return versionHash The EIP-712 hash of the stored offer
     * @return index The version index for the offered terms (always VERSION_CURRENT for NEW)
     */
    function _offerNew(bytes calldata _data) private returns (bytes16 agreementId, bytes32 versionHash, uint256 index) {
        RecurringCollectorStorage storage $ = _getStorage();
        RecurringCollectionAgreement memory rca = abi.decode(_data, (RecurringCollectionAgreement));

        (agreementId, versionHash) = _rcaIdAndHash(rca);

        if ($.rcaOffers[agreementId].offerHash != versionHash) {
            AgreementData storage agreement = $.agreements[agreementId];
            require(
                agreement.state == AgreementState.NotAccepted,
                RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
            );
            require(
                block.timestamp <= rca.deadline,
                RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rca.deadline)
            );
            _requireValidTerms(
                rca.deadline,
                rca.endsAt,
                rca.minSecondsPerCollection,
                rca.maxSecondsPerCollection,
                rca.payer,
                rca.conditions,
                rca.maxOngoingTokensPerSecond
            );

            agreement.payer = rca.payer;
            agreement.dataService = rca.dataService;
            agreement.serviceProvider = rca.serviceProvider;
            agreement.activeTermsHash = versionHash;

            $.rcaOffers[agreementId] = StoredOffer({ offerHash: versionHash, data: _data });
            emit OfferStored(agreementId, rca.payer, OFFER_TYPE_NEW, versionHash);
        }

        index = VERSION_CURRENT;
    }

    /**
     * @notice Process an update offer (OFFER_TYPE_UPDATE).
     * @param _data The ABI-encoded RecurringCollectionAgreementUpdate
     * @return agreementId The agreement ID being updated
     * @return versionHash The EIP-712 hash of the stored RCAU
     * @return index VERSION_NEXT, or VERSION_CURRENT if the RCAU has already been applied
     */
    function _offerUpdate(
        bytes calldata _data
    ) private returns (bytes16 agreementId, bytes32 versionHash, uint256 index) {
        RecurringCollectorStorage storage $ = _getStorage();
        RecurringCollectionAgreementUpdate memory rcau = abi.decode(_data, (RecurringCollectionAgreementUpdate));
        versionHash = _hashRCAU(rcau);
        agreementId = rcau.agreementId;
        AgreementData storage agreement = $.agreements[agreementId];

        if ($.rcauOffers[agreementId].offerHash != versionHash) {
            require(
                block.timestamp <= rcau.deadline,
                RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rcau.deadline)
            );
            address payer = agreement.payer;
            require(
                payer != address(0) &&
                    (agreement.state == AgreementState.NotAccepted || agreement.state == AgreementState.Accepted),
                RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
            );
            _requireValidTerms(
                rcau.deadline,
                rcau.endsAt,
                rcau.minSecondsPerCollection,
                rcau.maxSecondsPerCollection,
                payer,
                rcau.conditions,
                rcau.maxOngoingTokensPerSecond
            );

            $.rcauOffers[agreementId] = StoredOffer({ offerHash: versionHash, data: _data });
            emit OfferStored(agreementId, payer, OFFER_TYPE_UPDATE, versionHash);
        }

        // If the offered RCAU has already been applied, its hash matches activeTermsHash and the
        // version is now CURRENT, not NEXT (_versionHashAt(NEXT) would return 0 in that case).
        index = versionHash == agreement.activeTermsHash ? VERSION_CURRENT : VERSION_NEXT;
    }

    /// @inheritdoc IAgreementCollector
    /// @dev This implementation targets only the payer side of the agreement.
    /// SCOPE_PENDING and SCOPE_ACTIVE enforce `msg.sender == agreement.payer`.
    /// SCOPE_SIGNED has no caller check in this function; the entry it writes is
    /// self-keyed by msg.sender and is consulted only later, during payer
    /// authorization of a signed accept or update. Extending cancel to data-service
    /// or service-provider callers is left for a future revision.
    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 options) external whenNotPaused {
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        // Signed scope: record cancelledOffers[msg.sender][termsHash] = agreementId.
        // Self-authenticating — only blocks when msg.sender matches the recovered ECDSA signer.
        // The stored agreementId is checked in _requireAuthorization (!=); calling again
        // with bytes16(0) undoes the cancellation, calling with a different agreementId
        // redirects it.
        if (options & SCOPE_SIGNED != 0) {
            if ($.cancelledOffers[msg.sender][termsHash] != agreementId) {
                $.cancelledOffers[msg.sender][termsHash] = agreementId;
                emit OfferCancelled(msg.sender, agreementId, termsHash);
            }
        }

        // Pending / active scopes require payer authorization. No-op if nothing exists on-chain.
        address payer = agreement.payer;
        if (options & (SCOPE_PENDING | SCOPE_ACTIVE) == 0 || payer == address(0)) return;
        require(msg.sender == payer, RecurringCollectorUnauthorizedCaller(msg.sender, payer));

        if (agreement.activeTermsHash != termsHash || agreement.state == AgreementState.NotAccepted) {
            if (options & SCOPE_PENDING != 0) {
                // Pending scope: delete stored offer if hash matches and terms are not currently active
                if ($.rcaOffers[agreementId].offerHash == termsHash) {
                    delete $.rcaOffers[agreementId];
                    if (agreement.activeTermsHash == termsHash) agreement.activeTermsHash = bytes32(0);
                    emit OfferCancelled(msg.sender, agreementId, termsHash);
                } else if ($.rcauOffers[agreementId].offerHash == termsHash) {
                    delete $.rcauOffers[agreementId];
                    emit OfferCancelled(msg.sender, agreementId, termsHash);
                }
            }
        } else if (options & SCOPE_ACTIVE != 0 && agreement.state == AgreementState.Accepted)
            // Active scope and hash matches: cancel accepted agreement
            IDataServiceAgreements(agreement.dataService).cancelIndexingAgreementByPayer(agreementId);
    }

    /// @inheritdoc IAgreementCollector
    function getAgreementDetails(bytes16 agreementId, uint256 index) external view returns (AgreementDetails memory) {
        return _getAgreementDetails(agreementId, _versionHashAt(agreementId, index), index);
    }

    /**
     * @notice Builds AgreementDetails for the requested version. Shared by {offer} and
     * {getAgreementDetails}.
     * @dev Caller supplies the version hash. {offer} passes the hash returned by _offerNew /
     * _offerUpdate (already known from the just-stored offer); {getAgreementDetails} resolves
     * it via _versionHashAt. Returns empty details when versionHash is zero.
     * @param agreementId The agreement ID
     * @param versionHash The EIP-712 hash of the queried version, or bytes32(0) if none
     * @param index Version index (VERSION_CURRENT or VERSION_NEXT) — determines per-version flags
     * @return details AgreementDetails for the queried version, or empty when no version exists
     */
    function _getAgreementDetails(
        bytes16 agreementId,
        bytes32 versionHash,
        uint256 index
    ) private view returns (AgreementDetails memory details) {
        if (versionHash == bytes32(0)) return details;
        details.versionHash = versionHash;

        AgreementData storage agreement = _getStorage().agreements[agreementId];
        AgreementState agreementState = agreement.state;

        if (index == VERSION_CURRENT) {
            if (agreementState != AgreementState.NotAccepted)
                details.state = (0 < agreement.updateNonce) ? ACCEPTED | UPDATE : ACCEPTED;
        } else details.state = UPDATE;

        details.state |= REGISTERED;
        details.agreementId = agreementId;
        details.payer = agreement.payer;
        details.dataService = agreement.dataService;
        details.serviceProvider = agreement.serviceProvider;

        if (agreementState == AgreementState.CanceledByPayer) details.state |= NOTICE_GIVEN | BY_PAYER;
        else if (agreementState == AgreementState.CanceledByServiceProvider)
            details.state |= NOTICE_GIVEN | BY_PROVIDER;

        if (_getMaxNextClaimScoped(agreementId, index == VERSION_CURRENT ? SCOPE_ACTIVE : SCOPE_PENDING) == 0)
            details.state |= SETTLED;
    }

    /**
     * @notice Resolve the offer hash representing a given version (VERSION_CURRENT or VERSION_NEXT).
     * @dev Returns bytes32(0) when no version exists at that index. Pre-acceptance, activeTermsHash
     * mirrors rcaOffers.offerHash, so VERSION_CURRENT works uniformly across pre- and post-acceptance.
     * @param agreementId The agreement ID
     * @param index The version index (VERSION_CURRENT or VERSION_NEXT)
     * @return hash The EIP-712 hash of the offer at that version, or bytes32(0) if none
     */
    function _versionHashAt(bytes16 agreementId, uint256 index) private view returns (bytes32 hash) {
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        if (index == VERSION_CURRENT) hash = agreement.activeTermsHash;
        else if (index == VERSION_NEXT) {
            bytes32 rcauHash = $.rcauOffers[agreementId].offerHash;
            if (rcauHash != bytes32(0) && rcauHash != agreement.activeTermsHash) hash = rcauHash;
        }
    }

    /// @inheritdoc IAgreementCollector
    function getMaxNextClaim(bytes16 agreementId, uint8 agreementScope) external view returns (uint256) {
        return _getMaxNextClaimScoped(agreementId, agreementScope);
    }

    /// @inheritdoc IAgreementCollector
    function getAgreementOfferAt(
        bytes16 agreementId,
        uint256 index
    ) external view returns (uint8 offerType, bytes memory offerData) {
        bytes32 hash = _versionHashAt(agreementId, index);
        if (hash == bytes32(0)) return (OFFER_TYPE_NONE, "");

        RecurringCollectorStorage storage $ = _getStorage();
        StoredOffer storage rca = $.rcaOffers[agreementId];
        if (rca.offerHash == hash) return (OFFER_TYPE_NEW, rca.data);

        StoredOffer storage rcau = $.rcauOffers[agreementId];
        if (rcau.offerHash == hash) return (OFFER_TYPE_UPDATE, rcau.data);
    }

    /**
     * @notice Decodes the collect data.
     * @param data The encoded collect parameters.
     * @return The decoded collect parameters.
     */
    function decodeCollectData(bytes calldata data) public pure returns (CollectParams memory) {
        return abi.decode(data, (CollectParams));
    }

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
     * Emits {PaymentCollected} and {RCACollected} events.
     *
     * @param _paymentType The type of payment to collect
     * @param _params The decoded parameters for the collection
     * @return The amount of tokens collected
     */
    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        CollectParams memory _params
    ) private returns (uint256) {
        AgreementData storage agreement = _getAgreementStorage(_params.agreementId);

        // Check if agreement is collectable first
        (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason) = _getCollectionInfo(
            agreement
        );
        require(isCollectable, RecurringCollectorAgreementNotCollectable(_params.agreementId, reason));

        require(
            msg.sender == agreement.dataService,
            RecurringCollectorDataServiceNotAuthorized(_params.agreementId, msg.sender)
        );

        // Check the service provider has an active provision with the data service
        // This prevents an attack where the payer can deny the service provider from collecting payments
        // by using a signer as data service to syphon off the tokens in the escrow to an account they control
        {
            uint256 tokensAvailable = _graphStaking().getProviderTokensAvailable(
                agreement.serviceProvider,
                agreement.dataService
            );
            require(tokensAvailable > 0, RecurringCollectorUnauthorizedDataService(agreement.dataService));
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
            require(
                slippage <= _params.maxSlippage,
                RecurringCollectorExcessiveSlippage(_params.tokens, tokensToCollect, _params.maxSlippage)
            );
        }
        agreement.lastCollectionAt = uint64(block.timestamp);

        if (0 < tokensToCollect) {
            _preCollectCallbacks(agreement, _params.agreementId, tokensToCollect);

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

        emit PaymentCollected(
            _paymentType,
            _params.collectionId,
            agreement.payer,
            agreement.serviceProvider,
            agreement.dataService,
            tokensToCollect
        );

        emit RCACollected(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            _params.agreementId,
            _params.collectionId,
            tokensToCollect,
            _params.dataServiceCut
        );

        if (0 < tokensToCollect) _postCollectCallback(agreement.payer, _params.agreementId, tokensToCollect);
        return tokensToCollect;
    }
    /* solhint-enable function-max-lines */

    /**
     * @notice Validates that a contract payer supports IProviderEligibility via ERC-165.
     * @param payer The payer address to validate
     * @param conditions The conditions bitmask
     */
    function _requirePayerToSupportEligibilityCheck(address payer, uint16 conditions) private view {
        if (conditions & CONDITION_ELIGIBILITY_CHECK != 0) {
            require(
                ERC165Checker.supportsInterface(payer, type(IProviderEligibility).interfaceId),
                RecurringCollectorPayerDoesNotSupportEligibilityInterface(payer)
            );
        }
    }

    /**
     * @notice Executes pre-collection callbacks: eligibility check and beforeCollection notification.
     * @dev Extracted from _collect to reduce stack depth for coverage builds.
     * @param agreement The agreement storage data
     * @param agreementId The agreement ID
     * @param tokensToCollect The amount of tokens to collect
     */
    function _preCollectCallbacks(
        AgreementData storage agreement,
        bytes16 agreementId,
        uint256 tokensToCollect
    ) private {
        address payer = agreement.payer;
        address provider = agreement.serviceProvider;

        // Eligibility gate (opt-in via conditions bitmask). Assembly staticcall caps returndata
        // copy to 32 bytes, preventing returndata bombing. Only an explicit return of 0 blocks
        // collection; reverts, short returndata, and malformed responses are treated as "no
        // opinion" (collection proceeds).
        if ((agreement.conditions & CONDITION_ELIGIBILITY_CHECK) != 0) {
            if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD)
                revert RecurringCollectorInsufficientCallbackGas();
            bytes memory cd = abi.encodeCall(IProviderEligibility.isEligible, (provider));
            bool success;
            uint256 returnLen;
            uint256 result;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := staticcall(MAX_PAYER_CALLBACK_GAS, payer, add(cd, 0x20), mload(cd), 0x00, 0x20)
                returnLen := returndatasize()
                result := mload(0x00)
            }
            if (success && !(returnLen < 32) && result == 0)
                revert RecurringCollectorCollectionNotEligible(agreementId, provider);
            if (!success || returnLen < 32)
                emit PayerCallbackFailed(agreementId, payer, PayerCallbackStage.EligibilityCheck);
        }

        // Assembly call copies 0 bytes of returndata, preventing returndata bombing.
        if (payer.code.length != 0 && payer != msg.sender) {
            if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD)
                revert RecurringCollectorInsufficientCallbackGas();
            bytes memory cd = abi.encodeCall(IAgreementOwner.beforeCollection, (agreementId, tokensToCollect));
            bool beforeOk;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                beforeOk := call(MAX_PAYER_CALLBACK_GAS, payer, 0, add(cd, 0x20), mload(cd), 0, 0)
            }
            if (!beforeOk) emit PayerCallbackFailed(agreementId, payer, PayerCallbackStage.BeforeCollection);
        }
    }

    /**
     * @notice Executes post-collection callback: afterCollection notification.
     * @dev Extracted from _collect to reduce stack depth for coverage builds.
     * @param payer The payer address
     * @param agreementId The agreement ID
     * @param tokensToCollect The amount of tokens collected
     */
    function _postCollectCallback(address payer, bytes16 agreementId, uint256 tokensToCollect) private {
        // Notify contract payers so they can reconcile escrow in the same transaction.
        if (payer != msg.sender && payer.code.length != 0) {
            // 64/63 accounts for EIP-150 63/64 gas forwarding rule.
            if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63 + CALLBACK_GAS_OVERHEAD)
                revert RecurringCollectorInsufficientCallbackGas();
            // Assembly call copies 0 bytes of returndata, preventing returndata bombing.
            bytes memory afterCallData = abi.encodeCall(
                IAgreementOwner.afterCollection,
                (agreementId, tokensToCollect)
            );
            bool afterOk;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                afterOk := call(MAX_PAYER_CALLBACK_GAS, payer, 0, add(afterCallData, 0x20), mload(afterCallData), 0, 0)
            }
            if (!afterOk) emit PayerCallbackFailed(agreementId, payer, PayerCallbackStage.AfterCollection);
        }
    }

    /**
     * @notice Requires that the collection window parameters are valid.
     * @dev Validated against `_deadline` (the offer's acceptance deadline) rather than
     * `block.timestamp`, making this check time-independent: if terms pass here they remain
     * valid for any acceptance that happens on or before `_deadline`. Callers must enforce
     * `block.timestamp <= _deadline` at the acceptance entry point.
     * @param _deadline The offer's acceptance deadline
     * @param _endsAt The end time of the agreement
     * @param _minSecondsPerCollection The minimum seconds per collection
     * @param _maxSecondsPerCollection The maximum seconds per collection
     */
    function _requireValidCollectionWindowParams(
        uint64 _deadline,
        uint64 _endsAt,
        uint32 _minSecondsPerCollection,
        uint32 _maxSecondsPerCollection
    ) private pure {
        // Agreement must end after the deadline
        require(_deadline < _endsAt, RecurringCollectorAgreementEndsBeforeDeadline(_deadline, _endsAt));

        // Collection window needs to be at least MIN_SECONDS_COLLECTION_WINDOW
        require(
            _maxSecondsPerCollection > _minSecondsPerCollection &&
                (_maxSecondsPerCollection - _minSecondsPerCollection >= MIN_SECONDS_COLLECTION_WINDOW),
            RecurringCollectorAgreementInvalidCollectionWindow(
                MIN_SECONDS_COLLECTION_WINDOW,
                _minSecondsPerCollection,
                _maxSecondsPerCollection
            )
        );

        // Even if accepted at the deadline at least one min collection window must remain
        require(
            _minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW <= _endsAt - _deadline,
            RecurringCollectorAgreementInvalidDuration(
                _minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW,
                _endsAt - _deadline
            )
        );
    }

    /**
     * @notice Validates offer terms: collection window, eligibility support, and overflow.
     * @dev Called by _validateAndStoreAgreement and _validateAndStoreUpdate. Time-independent —
     * validates against the offer's deadline so the check is stable across the offer's lifetime.
     * @param _deadline The offer's acceptance deadline
     * @param _endsAt The end time of the agreement
     * @param _minSecondsPerCollection The minimum seconds per collection
     * @param _maxSecondsPerCollection The maximum seconds per collection
     * @param _payer The payer address (for eligibility validation)
     * @param _conditions The conditions bitmask
     * @param _maxOngoingTokensPerSecond The maximum ongoing tokens per second
     */
    function _requireValidTerms(
        uint64 _deadline,
        uint64 _endsAt,
        uint32 _minSecondsPerCollection,
        uint32 _maxSecondsPerCollection,
        address _payer,
        uint16 _conditions,
        uint256 _maxOngoingTokensPerSecond
    ) private view {
        _requireValidCollectionWindowParams(_deadline, _endsAt, _minSecondsPerCollection, _maxSecondsPerCollection);
        _requirePayerToSupportEligibilityCheck(_payer, _conditions);
        // Reverts on overflow — rejecting excessive terms that could prevent collection
        _maxOngoingTokensPerSecond * _maxSecondsPerCollection * 1024;
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
        AgreementData storage _agreement,
        bytes16 _agreementId,
        uint256 _tokens,
        uint256 _collectionSeconds
    ) private view returns (uint256) {
        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer ||
            block.timestamp > _agreement.endsAt;
        if (!canceledOrElapsed) {
            require(
                _collectionSeconds >= _agreement.minSecondsPerCollection,
                RecurringCollectorCollectionTooSoon(
                    _agreementId,
                    // casting to uint32 is safe because _collectionSeconds < minSecondsPerCollection (uint32)
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32(_collectionSeconds),
                    _agreement.minSecondsPerCollection
                )
            );
        }
        // _collectionSeconds is already capped at maxSecondsPerCollection by _getCollectionInfo
        uint256 maxTokens = _agreement.maxOngoingTokensPerSecond * _collectionSeconds;
        maxTokens += _agreement.lastCollectionAt == 0 ? _agreement.maxInitialTokens : 0;

        return Math.min(_tokens, maxTokens);
    }

    /**
     * @notice See {recoverRCASigner}
     * @param _rca The RCA whose hash was signed
     * @param _signature The ECDSA signature bytes
     * @return The address of the signer
     */
    function _recoverRCASigner(
        RecurringCollectionAgreement memory _rca,
        bytes memory _signature
    ) private view returns (address) {
        bytes32 messageHash = _hashRCA(_rca);
        return ECDSA.recover(messageHash, _signature);
    }

    /**
     * @notice See {recoverRCAUSigner}
     * @param _rcau The RCAU whose hash was signed
     * @param _signature The ECDSA signature bytes
     * @return The address of the signer
     */
    function _recoverRCAUSigner(
        RecurringCollectionAgreementUpdate memory _rcau,
        bytes memory _signature
    ) private view returns (address) {
        bytes32 messageHash = _hashRCAU(_rcau);
        return ECDSA.recover(messageHash, _signature);
    }

    /**
     * @notice See {hashRCA}
     * @param _rca The RCA to hash
     * @return The EIP712 hash of the RCA
     */
    function _hashRCA(RecurringCollectionAgreement memory _rca) private view returns (bytes32) {
        // Split abi.encode into two halves to avoid stack-too-deep without optimizer
        return
            _hashTypedDataV4(
                keccak256(
                    bytes.concat(
                        abi.encode(
                            EIP712_RCA_TYPEHASH,
                            _rca.deadline,
                            _rca.endsAt,
                            _rca.payer,
                            _rca.dataService,
                            _rca.serviceProvider,
                            _rca.maxInitialTokens
                        ),
                        abi.encode(
                            _rca.maxOngoingTokensPerSecond,
                            _rca.minSecondsPerCollection,
                            _rca.maxSecondsPerCollection,
                            _rca.conditions,
                            _rca.nonce,
                            keccak256(_rca.metadata)
                        )
                    )
                )
            );
    }

    /**
     * @notice See {hashRCAU}
     * @param _rcau The RCAU to hash
     * @return The EIP712 hash of the RCAU
     */
    function _hashRCAU(RecurringCollectionAgreementUpdate memory _rcau) private view returns (bytes32) {
        // Split abi.encode into two halves to avoid stack-too-deep without optimizer
        return
            _hashTypedDataV4(
                keccak256(
                    bytes.concat(
                        abi.encode(
                            EIP712_RCAU_TYPEHASH,
                            _rcau.agreementId,
                            _rcau.deadline,
                            _rcau.endsAt,
                            _rcau.maxInitialTokens,
                            _rcau.maxOngoingTokensPerSecond
                        ),
                        abi.encode(
                            _rcau.minSecondsPerCollection,
                            _rcau.maxSecondsPerCollection,
                            _rcau.conditions,
                            _rcau.nonce,
                            keccak256(_rcau.metadata)
                        )
                    )
                )
            );
    }

    /**
     * @notice Verifies authorization for an EIP712 hash using the given basis.
     * @param _payer The payer address (signer owner for ECDSA, contract for approval)
     * @param _hash The EIP712 typed data hash
     * @param _signature The ECDSA signature bytes, zero length for no signature (pre-approved via stored offer)
     * @param _agreementId The agreement ID (used to look up stored offer when not signed)
     * @param _offerType OFFER_TYPE_NEW or OFFER_TYPE_UPDATE (selects which stored offer to check)
     */
    function _requireAuthorization(
        address _payer,
        bytes32 _hash,
        bytes memory _signature,
        bytes16 _agreementId,
        uint8 _offerType
    ) private view {
        RecurringCollectorStorage storage $ = _getStorage();

        if (0 < _signature.length) {
            address signer = ECDSA.recover(_hash, _signature);
            require(_isAuthorized(_payer, signer), RecurringCollectorInvalidSigner());
            require($.cancelledOffers[signer][_hash] != _agreementId, RecurringCollectorOfferCancelled(signer, _hash));
        } else
            // Check stored offer hash instead of callback
            require(
                (_offerType == OFFER_TYPE_NEW ? $.rcaOffers[_agreementId] : $.rcauOffers[_agreementId]).offerHash ==
                    _hash,
                RecurringCollectorInvalidSigner()
            );
    }

    /**
     * @notice Validates that an agreement is in a valid state for updating and that the caller is authorized.
     * @param _agreementId The ID of the agreement to validate
     * @return The storage reference to the agreement data
     */
    function _requireValidUpdateTarget(bytes16 _agreementId) private view returns (AgreementData storage) {
        AgreementData storage agreement = _getAgreementStorage(_agreementId);
        require(
            agreement.state == AgreementState.Accepted,
            RecurringCollectorAgreementIncorrectState(_agreementId, agreement.state)
        );
        require(
            agreement.dataService == msg.sender,
            RecurringCollectorDataServiceNotAuthorized(_agreementId, msg.sender)
        );
        return agreement;
    }

    /**
     * @notice Validates and stores an update to a Recurring Collection Agreement.
     * Shared validation/storage/emit logic for the update function.
     * @param _agreement The storage reference to the agreement data
     * @param _rcau The Recurring Collection Agreement Update to apply
     * @param _rcauHash The EIP-712 hash of the RCAU
     */
    function _validateAndStoreUpdate(
        AgreementData storage _agreement,
        RecurringCollectionAgreementUpdate calldata _rcau,
        bytes32 _rcauHash
    ) private {
        RecurringCollectorStorage storage $ = _getStorage();

        _requireValidTerms(
            _rcau.deadline,
            _rcau.endsAt,
            _rcau.minSecondsPerCollection,
            _rcau.maxSecondsPerCollection,
            _agreement.payer,
            _rcau.conditions,
            _rcau.maxOngoingTokensPerSecond
        );

        // Clean up stored replaced offer. oldHash is always non-zero for accepted agreements
        // and can only ever survive in rcaOffers.
        if ($.rcaOffers[_rcau.agreementId].offerHash == _agreement.activeTermsHash)
            delete $.rcaOffers[_rcau.agreementId];

        // update the agreement terms
        _agreement.endsAt = _rcau.endsAt;
        _agreement.maxInitialTokens = _rcau.maxInitialTokens;
        _agreement.maxOngoingTokensPerSecond = _rcau.maxOngoingTokensPerSecond;
        _agreement.minSecondsPerCollection = _rcau.minSecondsPerCollection;
        _agreement.maxSecondsPerCollection = _rcau.maxSecondsPerCollection;
        _agreement.conditions = _rcau.conditions;
        _agreement.activeTermsHash = _rcauHash;
    }

    /**
     * @notice Gets an agreement to be updated.
     * @param _agreementId The ID of the agreement to get
     * @return The storage reference to the agreement data
     */
    function _getAgreementStorage(bytes16 _agreementId) private view returns (AgreementData storage) {
        return _getStorage().agreements[_agreementId];
    }

    /**
     * @notice See {getAgreement}
     * @param _agreementId The ID of the agreement to get
     * @return The agreement data
     */
    function _getAgreement(bytes16 _agreementId) private view returns (AgreementData memory) {
        return _getStorage().agreements[_agreementId];
    }

    /**
     * @notice Internal function to get collection info for an agreement.
     * @dev Single source of truth for collection window logic. The returned `collectionSeconds`
     * is capped at `maxSecondsPerCollection` — this is a cap on tokens, not a deadline; late
     * collections succeed but receive at most `maxSecondsPerCollection` worth of tokens.
     * @param _agreement The agreement data
     * @return isCollectable Whether the agreement can be collected from
     * @return collectionSeconds The valid collection duration in seconds, capped at
     * maxSecondsPerCollection (0 if not collectable)
     * @return reason The reason why the agreement is not collectable (None if collectable)
     */
    function _getCollectionInfo(
        AgreementData storage _agreement
    ) private view returns (bool, uint256, AgreementNotCollectableReason) {
        // Check if agreement is in collectable state
        bool hasValidState = _agreement.state == AgreementState.Accepted ||
            _agreement.state == AgreementState.CanceledByPayer;

        if (!hasValidState) {
            return (false, 0, AgreementNotCollectableReason.InvalidAgreementState);
        }

        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer ||
            block.timestamp > _agreement.endsAt;
        uint256 canceledOrNow = _agreement.state == AgreementState.CanceledByPayer
            ? _agreement.canceledAt
            : block.timestamp;

        uint256 collectionEnd = canceledOrElapsed ? Math.min(canceledOrNow, _agreement.endsAt) : block.timestamp;
        uint256 collectionStart = _agreementCollectionStartAt(_agreement);

        if (collectionEnd < collectionStart) {
            return (false, 0, AgreementNotCollectableReason.InvalidTemporalWindow);
        }

        if (collectionStart == collectionEnd) {
            return (false, 0, AgreementNotCollectableReason.ZeroCollectionSeconds);
        }

        uint256 elapsed = collectionEnd - collectionStart;
        return (
            true,
            Math.min(elapsed, uint256(_agreement.maxSecondsPerCollection)),
            AgreementNotCollectableReason.None
        );
    }

    /**
     * @notice Gets the start time for the collection of an agreement.
     * @param _agreement The agreement data
     * @return The start time for the collection of the agreement
     */
    function _agreementCollectionStartAt(AgreementData storage _agreement) private view returns (uint256) {
        return _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;
    }

    /**
     * @notice Compute the maximum tokens collectable in the next collection (worst case).
     * @dev Determines the collection window from agreement state, then delegates to {_maxClaim}.
     * Returns 0 for non-collectable states.
     * @param _a The agreement data
     * @return The maximum tokens that could be collected
     */
    function _getMaxNextClaim(AgreementData storage _a) private view returns (uint256) {
        // CanceledByServiceProvider = immediately non-collectable
        if (_a.state == AgreementState.CanceledByServiceProvider) return 0;
        // Only Accepted and CanceledByPayer are collectable
        if (_a.state != AgreementState.Accepted && _a.state != AgreementState.CanceledByPayer) return 0;

        uint256 collectionStart = _agreementCollectionStartAt(_a);

        // Determine the latest possible collection end
        uint256 collectionEnd;
        if (_a.state == AgreementState.CanceledByPayer) {
            // Payer cancel freezes the window at min(canceledAt, endsAt)
            collectionEnd = _a.canceledAt < _a.endsAt ? _a.canceledAt : _a.endsAt;
        } else {
            // Active: collection window capped at endsAt
            collectionEnd = _a.endsAt;
        }

        return
            _maxClaim(
                collectionStart,
                collectionEnd,
                _a.maxSecondsPerCollection,
                _a.maxOngoingTokensPerSecond,
                _a.lastCollectionAt == 0 ? _a.maxInitialTokens : 0
            );
    }

    /**
     * @notice Compute max next claim with scope control (active, pending, or both).
     * @dev Adapts the refactored _getMaxNextClaim(agreementId, agreementScope) pattern.
     * Active claim comes from the on-chain agreement state. Pending claim comes from
     * stored offers (RCA if not yet accepted, RCAU if pending update).
     * @param agreementId The agreement ID
     * @param agreementScope Bitmask: SCOPE_ACTIVE (1), SCOPE_PENDING (2), or both (3)
     * @return maxClaim The maximum tokens claimable under the requested scope
     */
    function _getMaxNextClaimScoped(bytes16 agreementId, uint8 agreementScope) private view returns (uint256 maxClaim) {
        if (agreementScope == 0) agreementScope = SCOPE_ACTIVE | SCOPE_PENDING;

        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage _a = $.agreements[agreementId];

        if (agreementScope & SCOPE_ACTIVE != 0) {
            if (_a.state == AgreementState.NotAccepted) {
                // Not yet accepted — check stored RCA offer
                StoredOffer storage rcaOffer = $.rcaOffers[agreementId];
                if (rcaOffer.offerHash != bytes32(0)) {
                    RecurringCollectionAgreement memory rca = abi.decode(rcaOffer.data, (RecurringCollectionAgreement));
                    if (block.timestamp <= rca.deadline)
                        maxClaim = _maxClaim(
                            block.timestamp,
                            rca.endsAt,
                            rca.maxSecondsPerCollection,
                            rca.maxOngoingTokensPerSecond,
                            rca.maxInitialTokens
                        );
                }
            } else maxClaim = _getMaxNextClaim(_a);
        }

        if (agreementScope & SCOPE_PENDING != 0) {
            StoredOffer storage rcauOffer = $.rcauOffers[agreementId];
            if (rcauOffer.offerHash != bytes32(0) && rcauOffer.offerHash != _a.activeTermsHash) {
                RecurringCollectionAgreementUpdate memory rcau = abi.decode(
                    rcauOffer.data,
                    (RecurringCollectionAgreementUpdate)
                );

                if (block.timestamp <= rcau.deadline) {
                    uint256 maxPendingClaim = _maxClaim(
                        block.timestamp,
                        rcau.endsAt,
                        rcau.maxSecondsPerCollection,
                        rcau.maxOngoingTokensPerSecond,
                        _a.lastCollectionAt == 0 ? rcau.maxInitialTokens : 0
                    );
                    if (maxClaim < maxPendingClaim) maxClaim = maxPendingClaim;
                }
            }
        }
    }

    /**
     * @notice Core claim formula: rate * min(window, maxSeconds) + initialBonus.
     * @dev Single source of truth for all max-claim calculations. Returns 0 when
     * windowEnd <= windowStart (empty or inverted window).
     * @param windowStart Start of the collection window
     * @param windowEnd End of the collection window
     * @param maxSecondsPerCollection Maximum seconds per collection period
     * @param maxOngoingTokensPerSecond Maximum ongoing tokens per second
     * @param maxInitialTokens Initial bonus tokens (0 if already collected)
     * @return The maximum possible claim amount
     */
    function _maxClaim(
        uint256 windowStart,
        uint256 windowEnd,
        uint256 maxSecondsPerCollection,
        uint256 maxOngoingTokensPerSecond,
        uint256 maxInitialTokens
    ) private pure returns (uint256) {
        if (windowEnd <= windowStart) return 0;
        uint256 windowSeconds = windowEnd - windowStart;
        uint256 effectiveSeconds = windowSeconds < maxSecondsPerCollection ? windowSeconds : maxSecondsPerCollection;
        return maxOngoingTokensPerSecond * effectiveSeconds + maxInitialTokens;
    }

    /**
     * @notice RC is self-authorized for any authorizer.
     * @dev Allows RC to call data service functions (e.g. cancelByPayer) that check
     * rc.isAuthorized(payer, msg.sender). When msg.sender is RC itself, this returns true,
     * meaning RC is trusted to have verified authorization before delegating.
     * @param authorizer The authorizer address
     * @param signer The signer address to check authorization for
     * @return True if the signer is authorized
     */
    function _isAuthorized(address authorizer, address signer) internal view override returns (bool) {
        if (signer == address(this)) return true;
        return super._isAuthorized(authorizer, signer);
    }

    /**
     * @notice Internal function to generate deterministic agreement ID
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param deadline The deadline for accepting the agreement
     * @param nonce A unique nonce for preventing collisions
     * @return agreementId The deterministically generated agreement ID
     */
    function _generateAgreementId(
        address payer,
        address dataService,
        address serviceProvider,
        uint64 deadline,
        uint256 nonce
    ) private pure returns (bytes16) {
        return bytes16(keccak256(abi.encode(payer, dataService, serviceProvider, deadline, nonce)));
    }

    /**
     * @notice Compute the agreement ID and EIP-712 hash for an RCA.
     * @dev These are always used together when accepting or offering an RCA.
     * @param _rca The Recurring Collection Agreement
     * @return agreementId The deterministic agreement ID
     * @return rcaHash The EIP-712 hash of the RCA
     */
    function _rcaIdAndHash(
        RecurringCollectionAgreement memory _rca
    ) private view returns (bytes16 agreementId, bytes32 rcaHash) {
        agreementId = _generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );
        rcaHash = _hashRCA(_rca);
    }
}
