// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
// solhint-disable-next-line no-unused-import
import { IPaymentsCollector } from "../../interfaces/IPaymentsCollector.sol"; // for @inheritdoc
import { IRecurringCollector } from "../../interfaces/IRecurringCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

/**
 * @title RecurringCollector contract
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCA (Recurring Collection Agreement).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is EIP712, GraphDirectory, Authorizable, IRecurringCollector {
    using PPMMath for uint256;

    /// @notice The minimum number of seconds that must be between two collections
    uint32 public constant MIN_SECONDS_COLLECTION_WINDOW = 600;

    /// @notice The EIP712 typehash for the RecurringCollectionAgreement struct
    bytes32 public constant EIP712_RCA_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreement(bytes16 agreementId,uint256 deadline,uint256 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
        );

    /// @notice The EIP712 typehash for the RecurringCollectionAgreementUpdate struct
    bytes32 public constant EIP712_RCAU_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
        );

    /// @notice Tracks agreements
    mapping(bytes16 agreementId => AgreementData data) public agreements;

    /**
     * @notice Constructs a new instance of the RecurringCollector contract.
     * @param eip712Name The name of the EIP712 domain.
     * @param eip712Version The version of the EIP712 domain.
     * @param controller The address of the Graph controller.
     * @param revokeSignerThawingPeriod The duration (in seconds) in which a signer is thawing before they can be revoked.
     */
    constructor(
        string memory eip712Name,
        string memory eip712Version,
        address controller,
        uint256 revokeSignerThawingPeriod
    ) EIP712(eip712Name, eip712Version) GraphDirectory(controller) Authorizable(revokeSignerThawingPeriod) {}

    /**
     * @inheritdoc IPaymentsCollector
     * @notice Initiate a payment collection through the payments protocol.
     * See {IPaymentsCollector.collect}.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes calldata data) external returns (uint256) {
        try this.decodeCollectData(data) returns (CollectParams memory collectParams) {
            return _collect(paymentType, collectParams);
        } catch {
            revert RecurringCollectorInvalidCollectData(data);
        }
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Accept an indexing agreement.
     * See {IRecurringCollector.accept}.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function accept(SignedRCA calldata signedRCA) external {
        require(signedRCA.rca.agreementId != bytes16(0), RecurringCollectorAgreementIdZero());
        require(
            msg.sender == signedRCA.rca.dataService,
            RecurringCollectorUnauthorizedCaller(msg.sender, signedRCA.rca.dataService)
        );
        require(
            signedRCA.rca.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, signedRCA.rca.deadline)
        );

        // check that the voucher is signed by the payer (or proxy)
        _requireAuthorizedRCASigner(signedRCA);

        require(
            signedRCA.rca.dataService != address(0) &&
                signedRCA.rca.payer != address(0) &&
                signedRCA.rca.serviceProvider != address(0),
            RecurringCollectorAgreementAddressNotSet()
        );

        _requireValidCollectionWindowParams(
            signedRCA.rca.endsAt,
            signedRCA.rca.minSecondsPerCollection,
            signedRCA.rca.maxSecondsPerCollection
        );

        AgreementData storage agreement = _getAgreementStorage(signedRCA.rca.agreementId);
        // check that the agreement is not already accepted
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(signedRCA.rca.agreementId, agreement.state)
        );

        // accept the agreement
        agreement.acceptedAt = uint64(block.timestamp);
        agreement.state = AgreementState.Accepted;
        agreement.dataService = signedRCA.rca.dataService;
        agreement.payer = signedRCA.rca.payer;
        agreement.serviceProvider = signedRCA.rca.serviceProvider;
        agreement.endsAt = signedRCA.rca.endsAt;
        agreement.maxInitialTokens = signedRCA.rca.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = signedRCA.rca.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = signedRCA.rca.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = signedRCA.rca.maxSecondsPerCollection;

        emit AgreementAccepted(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            signedRCA.rca.agreementId,
            agreement.acceptedAt,
            agreement.endsAt,
            agreement.maxInitialTokens,
            agreement.maxOngoingTokensPerSecond,
            agreement.minSecondsPerCollection,
            agreement.maxSecondsPerCollection
        );
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Cancel an indexing agreement.
     * See {IRecurringCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external {
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

        emit AgreementCanceled(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            agreementId,
            agreement.canceledAt,
            by
        );
    }

    /**
     * @inheritdoc IRecurringCollector
     * @notice Update an indexing agreement.
     * See {IRecurringCollector.update}.
     * @dev Caller must be the data service for the agreement.
     */
    function update(SignedRCAU calldata signedRCAU) external {
        require(
            signedRCAU.rcau.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, signedRCAU.rcau.deadline)
        );

        AgreementData storage agreement = _getAgreementStorage(signedRCAU.rcau.agreementId);
        require(
            agreement.state == AgreementState.Accepted,
            RecurringCollectorAgreementIncorrectState(signedRCAU.rcau.agreementId, agreement.state)
        );
        require(
            agreement.dataService == msg.sender,
            RecurringCollectorDataServiceNotAuthorized(signedRCAU.rcau.agreementId, msg.sender)
        );

        // check that the voucher is signed by the payer (or proxy)
        _requireAuthorizedRCAUSigner(signedRCAU, agreement.payer);

        _requireValidCollectionWindowParams(
            signedRCAU.rcau.endsAt,
            signedRCAU.rcau.minSecondsPerCollection,
            signedRCAU.rcau.maxSecondsPerCollection
        );

        // update the agreement
        agreement.endsAt = signedRCAU.rcau.endsAt;
        agreement.maxInitialTokens = signedRCAU.rcau.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = signedRCAU.rcau.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = signedRCAU.rcau.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = signedRCAU.rcau.maxSecondsPerCollection;

        emit AgreementUpdated(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            signedRCAU.rcau.agreementId,
            uint64(block.timestamp),
            agreement.endsAt,
            agreement.maxInitialTokens,
            agreement.maxOngoingTokensPerSecond,
            agreement.minSecondsPerCollection,
            agreement.maxSecondsPerCollection
        );
    }

    /// @inheritdoc IRecurringCollector
    function recoverRCASigner(SignedRCA calldata signedRCA) external view returns (address) {
        return _recoverRCASigner(signedRCA);
    }

    /// @inheritdoc IRecurringCollector
    function recoverRCAUSigner(SignedRCAU calldata signedRCAU) external view returns (address) {
        return _recoverRCAUSigner(signedRCAU);
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
    function isCollectable(AgreementData memory agreement) external pure returns (bool) {
        return _isCollectable(agreement);
    }

    /**
     * @notice Decodes the collect data.
     * @param data The encoded collect parameters.
     * @return The decoded collect parameters.
     */
    function decodeCollectData(bytes calldata data) public pure returns (CollectParams memory) {
        return abi.decode(data, (CollectParams));
    }

    /**
     * @notice Collect payment through the payments protocol.
     * @dev Caller must be the data service the RCA was issued to.
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
        require(
            _isCollectable(agreement),
            RecurringCollectorAgreementIncorrectState(_params.agreementId, agreement.state)
        );

        require(
            msg.sender == agreement.dataService,
            RecurringCollectorDataServiceNotAuthorized(_params.agreementId, msg.sender)
        );

        uint256 tokensToCollect = 0;
        if (_params.tokens != 0) {
            tokensToCollect = _requireValidCollect(agreement, _params.agreementId, _params.tokens);

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
        agreement.lastCollectionAt = uint64(block.timestamp);

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

        return tokensToCollect;
    }

    /**
     * @notice Requires that the collection window parameters are valid.
     *
     * @param _endsAt The end time of the agreement
     * @param _minSecondsPerCollection The minimum seconds per collection
     * @param _maxSecondsPerCollection The maximum seconds per collection
     */
    function _requireValidCollectionWindowParams(
        uint64 _endsAt,
        uint32 _minSecondsPerCollection,
        uint32 _maxSecondsPerCollection
    ) private view {
        // Agreement needs to end in the future
        require(_endsAt > block.timestamp, RecurringCollectorAgreementElapsedEndsAt(block.timestamp, _endsAt));

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

        // Agreement needs to last at least one min collection window
        require(
            _endsAt - block.timestamp >= _minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW,
            RecurringCollectorAgreementInvalidDuration(
                _minSecondsPerCollection + MIN_SECONDS_COLLECTION_WINDOW,
                _endsAt - block.timestamp
            )
        );
    }

    /**
     * @notice Requires that the collection params are valid.
     * @param _agreement The agreement data
     * @param _agreementId The ID of the agreement
     * @param _tokens The number of tokens to collect
     * @return The number of tokens that can be collected
     */
    function _requireValidCollect(
        AgreementData memory _agreement,
        bytes16 _agreementId,
        uint256 _tokens
    ) private view returns (uint256) {
        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer ||
            block.timestamp > _agreement.endsAt;
        uint256 canceledOrNow = _agreement.state == AgreementState.CanceledByPayer
            ? _agreement.canceledAt
            : block.timestamp;

        // if canceled by the payer allow collection till canceledAt
        // if elapsed allow collection till endsAt
        // if both are true, use the earlier one
        uint256 collectionEnd = canceledOrElapsed ? Math.min(canceledOrNow, _agreement.endsAt) : block.timestamp;
        uint256 collectionStart = _agreementCollectionStartAt(_agreement);
        require(
            collectionEnd != collectionStart,
            RecurringCollectorZeroCollectionSeconds(_agreementId, block.timestamp, uint64(collectionStart))
        );
        require(collectionEnd > collectionStart, RecurringCollectorFinalCollectionDone(_agreementId, collectionStart));

        uint256 collectionSeconds = collectionEnd - collectionStart;
        // Check that the collection window is long enough
        // If the agreement is canceled or elapsed, allow a shorter collection window
        if (!canceledOrElapsed) {
            require(
                collectionSeconds >= _agreement.minSecondsPerCollection,
                RecurringCollectorCollectionTooSoon(
                    _agreementId,
                    uint32(collectionSeconds),
                    _agreement.minSecondsPerCollection
                )
            );
        }
        require(
            collectionSeconds <= _agreement.maxSecondsPerCollection,
            RecurringCollectorCollectionTooLate(
                _agreementId,
                uint64(collectionSeconds),
                _agreement.maxSecondsPerCollection
            )
        );

        uint256 maxTokens = _agreement.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += _agreement.lastCollectionAt == 0 ? _agreement.maxInitialTokens : 0;

        return Math.min(_tokens, maxTokens);
    }

    /**
     * @notice See {recoverRCASigner}
     * @param _signedRCA The signed RCA to recover the signer from
     * @return The address of the signer
     */
    function _recoverRCASigner(SignedRCA memory _signedRCA) private view returns (address) {
        bytes32 messageHash = _hashRCA(_signedRCA.rca);
        return ECDSA.recover(messageHash, _signedRCA.signature);
    }

    /**
     * @notice See {recoverRCAUSigner}
     * @param _signedRCAU The signed RCAU to recover the signer from
     * @return The address of the signer
     */
    function _recoverRCAUSigner(SignedRCAU memory _signedRCAU) private view returns (address) {
        bytes32 messageHash = _hashRCAU(_signedRCAU.rcau);
        return ECDSA.recover(messageHash, _signedRCAU.signature);
    }

    /**
     * @notice See {hashRCA}
     * @param _rca The RCA to hash
     * @return The EIP712 hash of the RCA
     */
    function _hashRCA(RecurringCollectionAgreement memory _rca) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RCA_TYPEHASH,
                        _rca.agreementId,
                        _rca.deadline,
                        _rca.endsAt,
                        _rca.payer,
                        _rca.dataService,
                        _rca.serviceProvider,
                        _rca.maxInitialTokens,
                        _rca.maxOngoingTokensPerSecond,
                        _rca.minSecondsPerCollection,
                        _rca.maxSecondsPerCollection,
                        keccak256(_rca.metadata)
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
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RCAU_TYPEHASH,
                        _rcau.agreementId,
                        _rcau.deadline,
                        _rcau.endsAt,
                        _rcau.maxInitialTokens,
                        _rcau.maxOngoingTokensPerSecond,
                        _rcau.minSecondsPerCollection,
                        _rcau.maxSecondsPerCollection,
                        keccak256(_rcau.metadata)
                    )
                )
            );
    }

    /**
     * @notice Requires that the signer for the RCA is authorized
     * by the payer of the RCA.
     * @param _signedRCA The signed RCA to verify
     * @return The address of the authorized signer
     */
    function _requireAuthorizedRCASigner(SignedRCA memory _signedRCA) private view returns (address) {
        address signer = _recoverRCASigner(_signedRCA);
        require(_isAuthorized(_signedRCA.rca.payer, signer), RecurringCollectorInvalidSigner());

        return signer;
    }

    /**
     * @notice Requires that the signer for the RCAU is authorized
     * by the payer.
     * @param _signedRCAU The signed RCAU to verify
     * @param _payer The address of the payer
     * @return The address of the authorized signer
     */
    function _requireAuthorizedRCAUSigner(
        SignedRCAU memory _signedRCAU,
        address _payer
    ) private view returns (address) {
        address signer = _recoverRCAUSigner(_signedRCAU);
        require(_isAuthorized(_payer, signer), RecurringCollectorInvalidSigner());

        return signer;
    }

    /**
     * @notice Gets an agreement to be updated.
     * @param _agreementId The ID of the agreement to get
     * @return The storage reference to the agreement data
     */
    function _getAgreementStorage(bytes16 _agreementId) private view returns (AgreementData storage) {
        return agreements[_agreementId];
    }

    /**
     * @notice See {getAgreement}
     * @param _agreementId The ID of the agreement to get
     * @return The agreement data
     */
    function _getAgreement(bytes16 _agreementId) private view returns (AgreementData memory) {
        return agreements[_agreementId];
    }

    /**
     * @notice Gets the start time for the collection of an agreement.
     * @param _agreement The agreement data
     * @return The start time for the collection of the agreement
     */
    function _agreementCollectionStartAt(AgreementData memory _agreement) private pure returns (uint256) {
        return _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;
    }

    /**
     * @notice Requires that the agreement is collectable.
     * @param _agreement The agreement data
     * @return The boolean indicating if the agreement is collectable
     */
    function _isCollectable(AgreementData memory _agreement) private pure returns (bool) {
        return _agreement.state == AgreementState.Accepted || _agreement.state == AgreementState.CanceledByPayer;
    }
}
