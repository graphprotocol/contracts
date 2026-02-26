// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
// solhint-disable-next-line no-unused-import
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol"; // for @inheritdoc
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

/**
 * @title RecurringCollector contract
 * @author Edge & Node
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCA (Recurring Collection Agreement).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is EIP712, GraphDirectory, Authorizable, IRecurringCollector {
    using PPMMath for uint256;

    /// @notice The minimum number of seconds that must be between two collections
    uint32 public constant MIN_SECONDS_COLLECTION_WINDOW = 600;

    /* solhint-disable gas-small-strings */
    /// @notice The EIP712 typehash for the RecurringCollectionAgreement struct
    bytes32 public constant EIP712_RCA_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreement(uint64 deadline,uint64 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint256 nonce,bytes metadata)"
        );

    /// @notice The EIP712 typehash for the RecurringCollectionAgreementUpdate struct
    bytes32 public constant EIP712_RCAU_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreementUpdate(bytes16 agreementId,uint64 deadline,uint64 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,uint32 nonce,bytes metadata)"
        );
    /* solhint-enable gas-small-strings */

    /// @notice Tracks agreements
    mapping(bytes16 agreementId => AgreementData data) internal agreements;

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

    /* solhint-disable function-max-lines */
    /**
     * @inheritdoc IRecurringCollector
     * @notice Accept a Recurring Collection Agreement.
     * See {IRecurringCollector.accept}.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function accept(SignedRCA calldata signedRCA) external returns (bytes16) {
        bytes16 agreementId = _generateAgreementId(
            signedRCA.rca.payer,
            signedRCA.rca.dataService,
            signedRCA.rca.serviceProvider,
            signedRCA.rca.deadline,
            signedRCA.rca.nonce
        );

        require(agreementId != bytes16(0), RecurringCollectorAgreementIdZero());
        require(
            msg.sender == signedRCA.rca.dataService,
            RecurringCollectorUnauthorizedCaller(msg.sender, signedRCA.rca.dataService)
        );
        /* solhint-disable gas-strict-inequalities */
        require(
            signedRCA.rca.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, signedRCA.rca.deadline)
        );
        /* solhint-enable gas-strict-inequalities */

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

        AgreementData storage agreement = _getAgreementStorage(agreementId);
        // check that the agreement is not already accepted
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
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
        agreement.updateNonce = 0;

        emit AgreementAccepted(
            agreement.dataService,
            agreement.payer,
            agreement.serviceProvider,
            agreementId,
            agreement.acceptedAt,
            agreement.endsAt,
            agreement.maxInitialTokens,
            agreement.maxOngoingTokensPerSecond,
            agreement.minSecondsPerCollection,
            agreement.maxSecondsPerCollection
        );

        return agreementId;
    }
    /* solhint-enable function-max-lines */

    /**
     * @inheritdoc IRecurringCollector
     * @notice Cancel a Recurring Collection Agreement.
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

    /* solhint-disable function-max-lines */
    /**
     * @inheritdoc IRecurringCollector
     * @notice Update a Recurring Collection Agreement.
     * See {IRecurringCollector.update}.
     * @dev Caller must be the data service for the agreement.
     * @dev Note: Updated pricing terms apply immediately and will affect the next collection
     * for the entire period since lastCollectionAt.
     */
    function update(SignedRCAU calldata signedRCAU) external {
        /* solhint-disable gas-strict-inequalities */
        require(
            signedRCAU.rcau.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, signedRCAU.rcau.deadline)
        );
        /* solhint-enable gas-strict-inequalities */

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

        // validate nonce to prevent replay attacks
        uint32 expectedNonce = agreement.updateNonce + 1;
        require(
            signedRCAU.rcau.nonce == expectedNonce,
            RecurringCollectorInvalidUpdateNonce(signedRCAU.rcau.agreementId, expectedNonce, signedRCAU.rcau.nonce)
        );

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
        agreement.updateNonce = signedRCAU.rcau.nonce;

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
    /* solhint-enable function-max-lines */

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
    function getCollectionInfo(
        AgreementData calldata agreement
    ) external view returns (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason) {
        return _getCollectionInfo(agreement);
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

        uint256 tokensToCollect = 0;
        if (_params.tokens != 0) {
            tokensToCollect = _requireValidCollect(agreement, _params.agreementId, _params.tokens, collectionSeconds);

            uint256 slippage = _params.tokens - tokensToCollect;
            /* solhint-disable gas-strict-inequalities */
            require(
                slippage <= _params.maxSlippage,
                RecurringCollectorExcessiveSlippage(_params.tokens, tokensToCollect, _params.maxSlippage)
            );
            /* solhint-enable gas-strict-inequalities */
        }
        agreement.lastCollectionAt = uint64(block.timestamp);

        if (tokensToCollect > 0) {
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

        return tokensToCollect;
    }
    /* solhint-enable function-max-lines */

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
                // solhint-disable-next-line gas-strict-inequalities
                (_maxSecondsPerCollection - _minSecondsPerCollection >= MIN_SECONDS_COLLECTION_WINDOW),
            RecurringCollectorAgreementInvalidCollectionWindow(
                MIN_SECONDS_COLLECTION_WINDOW,
                _minSecondsPerCollection,
                _maxSecondsPerCollection
            )
        );

        // Agreement needs to last at least one min collection window
        require(
            // solhint-disable-next-line gas-strict-inequalities
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
     * @param _collectionSeconds Collection duration from _getCollectionInfo()
     * @return The number of tokens that can be collected
     */
    function _requireValidCollect(
        AgreementData memory _agreement,
        bytes16 _agreementId,
        uint256 _tokens,
        uint256 _collectionSeconds
    ) private view returns (uint256) {
        bool canceledOrElapsed = _agreement.state == AgreementState.CanceledByPayer ||
            block.timestamp > _agreement.endsAt;
        if (!canceledOrElapsed) {
            require(
                // solhint-disable-next-line gas-strict-inequalities
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
        require(
            // solhint-disable-next-line gas-strict-inequalities
            _collectionSeconds <= _agreement.maxSecondsPerCollection,
            RecurringCollectorCollectionTooLate(
                _agreementId,
                uint64(_collectionSeconds),
                _agreement.maxSecondsPerCollection
            )
        );

        uint256 maxTokens = _agreement.maxOngoingTokensPerSecond * _collectionSeconds;
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
                        _rca.deadline,
                        _rca.endsAt,
                        _rca.payer,
                        _rca.dataService,
                        _rca.serviceProvider,
                        _rca.maxInitialTokens,
                        _rca.maxOngoingTokensPerSecond,
                        _rca.minSecondsPerCollection,
                        _rca.maxSecondsPerCollection,
                        _rca.nonce,
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
                        _rcau.nonce,
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
     * @notice Internal function to get collection info for an agreement
     * @dev This is the single source of truth for collection window logic
     * @param _agreement The agreement data
     * @return isCollectable Whether the agreement can be collected from
     * @return collectionSeconds The valid collection duration in seconds (0 if not collectable)
     * @return reason The reason why the agreement is not collectable (None if collectable)
     */
    function _getCollectionInfo(
        AgreementData memory _agreement
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

        return (true, collectionEnd - collectionStart, AgreementNotCollectableReason.None);
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
