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
    VERSION_CURRENT,
    VERSION_NEXT,
    SCOPE_ACTIVE,
    SCOPE_PENDING
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

    /// @notice Decoded agreement terms keyed by EIP-712 hash. `data` preserves the
    /// original ABI-encoded RCA or RCAU for {getAgreementOfferAt} consumers.
    struct AgreementTerms {
        uint8 offerType; //                    1 byte  ─┐ slot 0 (27/32)
        uint64 endsAt; //                      8 bytes ─┤
        uint64 deadline; //                    8 bytes ─┤
        uint32 minSecondsPerCollection; //     4 bytes ─┤
        uint32 maxSecondsPerCollection; //     4 bytes ─┤
        uint16 conditions; //                  2 bytes ─┘
        uint256 maxInitialTokens; //          32 bytes ── slot 1
        uint256 maxOngoingTokensPerSecond; // 32 bytes ── slot 2
        bytes data; //                                 ── slot 3 (pointer)
    }

    /// @custom:storage-location erc7201:graphprotocol.storage.RecurringCollector
    struct RecurringCollectorStorage {
        /// @notice List of pause guardians and their allowed status
        mapping(address pauseGuardian => bool allowed) pauseGuardians;
        /// @notice Tracks agreements
        mapping(bytes16 agreementId => AgreementData data) agreements;
        /// @notice Decoded agreement terms, keyed by EIP-712 hash.
        /// Referenced by AgreementData.activeTermsHash and pendingTermsHash.
        mapping(bytes32 termsHash => AgreementTerms terms) terms;
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
        require(
            block.timestamp <= rca.deadline,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rca.deadline)
        );
        require(msg.sender == rca.dataService, RecurringCollectorUnauthorizedCaller(msg.sender, rca.dataService));

        bytes32 rcaHash;
        (agreementId, rcaHash) = _rcaIdAndHash(rca);

        _requireAuthorization(rca.payer, rcaHash, signature, agreementId, OFFER_TYPE_NEW);

        if (_validateAndStoreTerms(agreementId, rcaHash, _termsFromRCA(rca), rca.payer, VERSION_CURRENT, rca.deadline))
            _storeAgreement(agreementId, rca);

        AgreementData storage agreement = _getStorage().agreements[agreementId];
        // Idempotent: already accepted → return silently
        if (agreement.state == AgreementState.Accepted) return agreementId;
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );
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
     * @notice Stores agreement participants and state identity. Does not store terms or hashes.
     * @param agreementId The agreement ID
     * @param rca The Recurring Collection Agreement (source for identity fields)
     */
    function _storeAgreement(bytes16 agreementId, RecurringCollectionAgreement memory rca) private {
        require(
            rca.dataService != address(0) && rca.payer != address(0) && rca.serviceProvider != address(0),
            RecurringCollectorAgreementAddressNotSet()
        );

        AgreementData storage agreement = _getAgreementStorage(agreementId);
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );

        agreement.dataService = rca.dataService;
        agreement.payer = rca.payer;
        agreement.serviceProvider = rca.serviceProvider;
        agreement.updateNonce = 0;
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Cancel a Recurring Collection Agreement.
     * See {IRecurringCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external whenNotPaused {
        AgreementData storage agreement = _getAgreementStorage(agreementId);
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
        if (agreement.pendingTermsHash == rcauHash) {
            // Accept pending offer: move hash from pending to active (terms already stored + validated)
            delete $.terms[agreement.activeTermsHash];
            agreement.activeTermsHash = rcauHash;
            agreement.pendingTermsHash = bytes32(0);
        } else
            _validateAndStoreTerms(
                rcau.agreementId,
                rcauHash,
                _termsFromRCAU(rcau),
                agreement.payer,
                VERSION_CURRENT,
                rcau.deadline
            );

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
        if (offerType == OFFER_TYPE_NEW) details = _offerNew(data);
        else if (offerType == OFFER_TYPE_UPDATE) details = _offerUpdate(data);
        else revert RecurringCollectorInvalidCollectData(data);

        require(msg.sender == details.payer, RecurringCollectorUnauthorizedCaller(msg.sender, details.payer));
    }

    /**
     * @notice Process a new offer (OFFER_TYPE_NEW).
     * @param _data The ABI-encoded RecurringCollectionAgreement
     * @return details The agreement details
     */
    function _offerNew(bytes calldata _data) private returns (AgreementDetails memory details) {
        RecurringCollectionAgreement memory rca = abi.decode(_data, (RecurringCollectionAgreement));
        require(
            block.timestamp <= rca.deadline,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rca.deadline)
        );

        (bytes16 agreementId, bytes32 rcaHash) = _rcaIdAndHash(rca);

        if (
            _validateAndStoreTerms(agreementId, rcaHash, _termsFromRCA(rca), rca.payer, VERSION_CURRENT, rca.deadline)
        ) {
            _storeAgreement(agreementId, rca);
            emit OfferStored(agreementId, rca.payer, OFFER_TYPE_NEW, rcaHash);
        }

        return _getAgreementDetails(_getStorage(), agreementId, rcaHash);
    }

    /**
     * @notice Process an update offer (OFFER_TYPE_UPDATE).
     * @param _data The ABI-encoded RecurringCollectionAgreementUpdate
     * @return details The agreement details
     */
    function _offerUpdate(bytes calldata _data) private returns (AgreementDetails memory details) {
        RecurringCollectionAgreementUpdate memory rcau = abi.decode(_data, (RecurringCollectionAgreementUpdate));
        require(
            block.timestamp <= rcau.deadline,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rcau.deadline)
        );
        bytes16 agreementId = rcau.agreementId;

        AgreementData storage agreement = _getStorage().agreements[agreementId];
        address payer = agreement.payer;

        bytes32 offerHash = _hashRCAU(rcau);

        if (_validateAndStoreTerms(agreementId, offerHash, _termsFromRCAU(rcau), payer, VERSION_NEXT, rcau.deadline))
            emit OfferStored(agreementId, payer, OFFER_TYPE_UPDATE, offerHash);

        return _getAgreementDetails(_getStorage(), agreementId, offerHash);
    }

    /// @inheritdoc IAgreementCollector
    function cancel(bytes16 agreementId, bytes32 termsHash, uint16 options) external whenNotPaused {
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        // Pending / active scopes: revert if on-chain data exists but caller is not the payer.
        // No-op if nothing exists on-chain (nothing to cancel).
        if (options & (SCOPE_PENDING | SCOPE_ACTIVE) != 0) {
            address payer = agreement.payer;
            if (payer == address(0)) return;
            require(payer == msg.sender, RecurringCollectorUnauthorizedCaller(msg.sender, payer));
        }

        if (options & SCOPE_PENDING != 0) {
            if (agreement.pendingTermsHash == termsHash) {
                // Pending update matches — delete it.
                delete $.terms[termsHash];
                agreement.pendingTermsHash = bytes32(0);
                emit OfferCancelled(msg.sender, agreementId, termsHash);
            } else if (agreement.activeTermsHash == termsHash && agreement.state == AgreementState.NotAccepted) {
                // Pre-acceptance RCA offer matches — delete it. Any pending RCAU is
                // independent and can be cancelled separately in either order.
                delete $.terms[termsHash];
                agreement.activeTermsHash = bytes32(0);
                emit OfferCancelled(msg.sender, agreementId, termsHash);
            }
        }
        if (
            options & SCOPE_ACTIVE != 0 &&
            agreement.state == AgreementState.Accepted &&
            agreement.activeTermsHash == termsHash
        )
            // Active scope and hash matches accepted agreement — cancel via data service.
            IDataServiceAgreements(agreement.dataService).cancelIndexingAgreementByPayer(agreementId);
    }

    /// @inheritdoc IAgreementCollector
    function getAgreementDetails(
        bytes16 agreementId,
        uint256 index
    ) external view returns (AgreementDetails memory details) {
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        return _getAgreementDetails($, agreementId, _getVersionHash(agreement, index));
    }

    /**
     * @notice Build an AgreementDetails view for a given version hash.
     * @dev Empty struct when no offer is stored for the version. Otherwise composes state flags
     * per the {IAgreementCollector} flag spec. Shared by getAgreementDetails, _offerNew, and
     * _offerUpdate so all three consistently reflect the same on-chain state.
     * @param $ The collector storage root
     * @param agreementId The agreement ID
     * @param versionHash The version hash (activeTermsHash or pendingTermsHash)
     * @return details The composed agreement details
     */
    // solhint-disable-next-line use-natspec
    function _getAgreementDetails(
        RecurringCollectorStorage storage $,
        bytes16 agreementId,
        bytes32 versionHash
    ) private view returns (AgreementDetails memory details) {
        uint8 offerType = $.terms[versionHash].offerType;
        if (offerType == OFFER_TYPE_NONE) return details;

        AgreementData storage agreement = $.agreements[agreementId];
        AgreementState agreementState = agreement.state;

        details.agreementId = agreementId;
        details.versionHash = versionHash;
        details.payer = agreement.payer;
        details.dataService = agreement.dataService;
        details.serviceProvider = agreement.serviceProvider;

        details.state = REGISTERED;
        if (agreementState != AgreementState.NotAccepted && versionHash == agreement.activeTermsHash)
            details.state |= ACCEPTED;

        if (offerType == OFFER_TYPE_UPDATE) details.state |= UPDATE;

        if (agreementState == AgreementState.CanceledByPayer) details.state |= NOTICE_GIVEN | BY_PAYER;
        else if (agreementState == AgreementState.CanceledByServiceProvider)
            details.state |= NOTICE_GIVEN | BY_PROVIDER;

        if (_getMaxNextClaimScoped(agreementId, 0) == 0) details.state |= SETTLED;
    }

    /**
     * @notice Resolves a version index to the corresponding terms hash.
     * @dev Returns bytes32(0) for unknown indexes or when the slot is empty.
     * @param agreement The agreement data
     * @param index The version index ({VERSION_CURRENT} or {VERSION_NEXT})
     * @return versionHash The resolved terms hash
     */
    function _getVersionHash(
        AgreementData storage agreement,
        uint256 index
    ) private view returns (bytes32 versionHash) {
        if (index == VERSION_CURRENT) versionHash = agreement.activeTermsHash;
        else if (index == VERSION_NEXT) versionHash = agreement.pendingTermsHash;
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
        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage agreement = $.agreements[agreementId];

        bytes32 versionHash = _getVersionHash(agreement, index);
        if (versionHash == bytes32(0)) return (OFFER_TYPE_NONE, "");

        AgreementTerms storage stored = $.terms[versionHash];
        return (stored.offerType, stored.data);
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
        if ((_getStorage().terms[agreement.activeTermsHash].conditions & CONDITION_ELIGIBILITY_CHECK) != 0) {
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
     * @dev Called once per unique hash by _validateAndStoreTerms (on first store). Time-independent
     * — validates against the offer's deadline.
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

    /// @notice Extract AgreementTerms from an RCA.
    /// @param rca The Recurring Collection Agreement
    /// @return terms The decoded agreement terms
    function _termsFromRCA(RecurringCollectionAgreement memory rca) private pure returns (AgreementTerms memory terms) {
        terms.offerType = OFFER_TYPE_NEW;
        terms.endsAt = rca.endsAt;
        terms.deadline = rca.deadline;
        terms.minSecondsPerCollection = rca.minSecondsPerCollection;
        terms.maxSecondsPerCollection = rca.maxSecondsPerCollection;
        terms.conditions = rca.conditions;
        terms.maxInitialTokens = rca.maxInitialTokens;
        terms.maxOngoingTokensPerSecond = rca.maxOngoingTokensPerSecond;
        terms.data = abi.encode(rca);
    }

    /// @notice Extract AgreementTerms from an RCAU.
    /// @param rcau The Recurring Collection Agreement Update
    /// @return terms The decoded agreement terms
    function _termsFromRCAU(
        RecurringCollectionAgreementUpdate memory rcau
    ) private pure returns (AgreementTerms memory terms) {
        terms.offerType = OFFER_TYPE_UPDATE;
        terms.endsAt = rcau.endsAt;
        terms.deadline = rcau.deadline;
        terms.minSecondsPerCollection = rcau.minSecondsPerCollection;
        terms.maxSecondsPerCollection = rcau.maxSecondsPerCollection;
        terms.conditions = rcau.conditions;
        terms.maxInitialTokens = rcau.maxInitialTokens;
        terms.maxOngoingTokensPerSecond = rcau.maxOngoingTokensPerSecond;
        terms.data = abi.encode(rcau);
    }

    /**
     * @notice Validates temporal constraints and caps the requested token amount.
     * @dev Enforces `minSecondsPerCollection` (unless canceled/elapsed) and returns the lesser of
     * the requested amount and the RCA payer's per-collection cap
     * (`maxOngoingTokensPerSecond * collectionSeconds`, plus `maxInitialTokens` on first collection).
     * @param _agreement The agreement data (lifecycle)
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
        AgreementTerms storage terms = _getStorage().terms[_agreement.activeTermsHash];
        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer || block.timestamp > terms.endsAt;
        if (!canceledOrElapsed) {
            require(
                _collectionSeconds >= terms.minSecondsPerCollection,
                RecurringCollectorCollectionTooSoon(
                    _agreementId,
                    // casting to uint32 is safe because _collectionSeconds < minSecondsPerCollection (uint32)
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint32(_collectionSeconds),
                    terms.minSecondsPerCollection
                )
            );
        }
        // _collectionSeconds is already capped at maxSecondsPerCollection by _getCollectionInfo
        uint256 maxTokens = terms.maxOngoingTokensPerSecond * _collectionSeconds;
        maxTokens += _agreement.lastCollectionAt == 0 ? terms.maxInitialTokens : 0;

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
     * @param _signature The ECDSA signature, zero length for no signature (pre-approved via stored terms)
     * @param _agreementId The agreement ID (used to look up stored terms when not signed)
     * @param _offerType OFFER_TYPE_NEW or OFFER_TYPE_UPDATE (selects which terms hash to check)
     */
    function _requireAuthorization(
        address _payer,
        bytes32 _hash,
        bytes memory _signature,
        bytes16 _agreementId,
        uint8 _offerType
    ) private view {
        if (0 < _signature.length)
            require(_isAuthorized(_payer, ECDSA.recover(_hash, _signature)), RecurringCollectorInvalidSigner());
        else {
            // Pre-approval: the hash must match the expected version of this agreement.
            AgreementData storage agreement = _getStorage().agreements[_agreementId];
            bytes32 versionHash = _offerType == OFFER_TYPE_NEW ? agreement.activeTermsHash : agreement.pendingTermsHash;
            require(versionHash == _hash, RecurringCollectorInvalidSigner());
        }
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
     * @notice Validate, store, and link agreement terms to a version slot.
     * @dev Idempotent: if the hash is already stored for this agreement (in any slot), returns
     * false without side effects. Validation is time-independent (uses deadline) so terms only
     * need validating once — on first store. Caller must separately handle the "accept pending
     * into active" transition (done in {update}): this function is only for storing new terms.
     * @param agreementId The agreement ID
     * @param hash The EIP-712 terms hash
     * @param newTerms The decoded terms to store
     * @param payer The payer address (for eligibility validation)
     * @param index The version slot to link: {VERSION_CURRENT} (active) or {VERSION_NEXT} (pending).
     * @param deadline The offer deadline (for offer-window validation)
     * @return added False if the hash was already stored (idempotent no-op).
     */
    function _validateAndStoreTerms(
        bytes16 agreementId,
        bytes32 hash,
        AgreementTerms memory newTerms,
        address payer,
        uint256 index,
        uint64 deadline
    ) private returns (bool added) {
        RecurringCollectorStorage storage $ = _getStorage();

        if ($.terms[hash].offerType != OFFER_TYPE_NONE) return false;

        _requireValidTerms(
            deadline,
            newTerms.endsAt,
            newTerms.minSecondsPerCollection,
            newTerms.maxSecondsPerCollection,
            payer,
            newTerms.conditions,
            newTerms.maxOngoingTokensPerSecond
        );
        $.terms[hash] = newTerms;

        AgreementData storage agreement = $.agreements[agreementId];
        if (index == VERSION_NEXT) {
            if (agreement.pendingTermsHash != bytes32(0)) delete $.terms[agreement.pendingTermsHash];
            agreement.pendingTermsHash = hash;
        } else {
            if (agreement.activeTermsHash != bytes32(0)) delete $.terms[agreement.activeTermsHash];
            agreement.activeTermsHash = hash;
        }
        return true;
    }

    /**
     * @notice Gets an agreement storage reference.
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
     * @param _agreement The agreement data (lifecycle); terms loaded from terms[activeTermsHash]
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

        AgreementTerms storage _terms = _getStorage().terms[_agreement.activeTermsHash];

        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer || block.timestamp > _terms.endsAt;
        uint256 canceledOrNow = _agreement.state == AgreementState.CanceledByPayer
            ? _agreement.canceledAt
            : block.timestamp;

        uint256 collectionEnd = canceledOrElapsed ? Math.min(canceledOrNow, _terms.endsAt) : block.timestamp;
        uint256 collectionStart = _agreementCollectionStartAt(_agreement);

        if (collectionEnd < collectionStart) {
            return (false, 0, AgreementNotCollectableReason.InvalidTemporalWindow);
        }

        if (collectionStart == collectionEnd) {
            return (false, 0, AgreementNotCollectableReason.ZeroCollectionSeconds);
        }

        uint256 elapsed = collectionEnd - collectionStart;
        return (true, Math.min(elapsed, uint256(_terms.maxSecondsPerCollection)), AgreementNotCollectableReason.None);
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
     * @notice Compute max next claim with scope control (active, pending, or both).
     * @dev Terms are loaded from terms[hash]. Active window is state-dependent (pre-acceptance
     * time-caps from now; accepted starts from last collection; cancelled caps at canceledAt or
     * yields a zero-width window). Pending window is always time-capped from now to endsAt.
     * @param agreementId The agreement ID
     * @param agreementScope Bitmask: SCOPE_ACTIVE (1), SCOPE_PENDING (2), or both (3)
     * @return maxClaim The maximum tokens claimable under the requested scope
     */
    function _getMaxNextClaimScoped(bytes16 agreementId, uint8 agreementScope) private view returns (uint256 maxClaim) {
        if (agreementScope == 0) agreementScope = SCOPE_ACTIVE | SCOPE_PENDING;

        RecurringCollectorStorage storage $ = _getStorage();
        AgreementData storage _a = $.agreements[agreementId];
        bool hasCollected = _a.lastCollectionAt != 0;

        if (agreementScope & SCOPE_ACTIVE != 0 && _a.activeTermsHash != bytes32(0)) {
            AgreementTerms storage terms = $.terms[_a.activeTermsHash];
            AgreementState state = _a.state;
            // Pre-acceptance: claimable until deadline (else start == end → zero window).
            // Accepted / CanceledByPayer: start from last collection (or acceptedAt).
            uint256 start = state == AgreementState.NotAccepted
                ? (block.timestamp < terms.deadline ? block.timestamp : terms.endsAt)
                : _agreementCollectionStartAt(_a);
            // CanceledByServiceProvider: zero window (end == start). CanceledByPayer: cap at canceledAt.
            uint256 end = state == AgreementState.CanceledByServiceProvider
                ? start
                : (
                    state == AgreementState.CanceledByPayer && _a.canceledAt < terms.endsAt
                        ? _a.canceledAt
                        : terms.endsAt
                );
            maxClaim = _maxClaimForTerms(start, end, terms, hasCollected);
        }

        if (agreementScope & SCOPE_PENDING != 0 && _a.pendingTermsHash != bytes32(0)) {
            AgreementTerms storage terms = $.terms[_a.pendingTermsHash];
            uint256 pending = _maxClaimForTerms(block.timestamp, terms.endsAt, terms, hasCollected);
            if (maxClaim < pending) maxClaim = pending;
        }
    }

    /**
     * @notice Compute max claim from a window and agreement terms.
     * @param windowStart Start of the collection window
     * @param windowEnd End of the collection window
     * @param terms The agreement terms
     * @param hasCollected Whether a collection has already occurred (suppresses initial bonus)
     * @return maxClaim The maximum possible claim amount
     */
    function _maxClaimForTerms(
        uint256 windowStart,
        uint256 windowEnd,
        AgreementTerms storage terms,
        bool hasCollected
    ) private view returns (uint256 maxClaim) {
        if (windowEnd <= windowStart) return 0;
        uint256 windowSeconds = windowEnd - windowStart;
        uint256 effectiveSeconds = windowSeconds < terms.maxSecondsPerCollection
            ? windowSeconds
            : terms.maxSecondsPerCollection;
        maxClaim = terms.maxOngoingTokensPerSecond * effectiveSeconds;
        if (!hasCollected) maxClaim += terms.maxInitialTokens;
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
