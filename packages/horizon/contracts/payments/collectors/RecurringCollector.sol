// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IRecurringCollector } from "../../interfaces/IRecurringCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";
import { MathUtils } from "../../libraries/MathUtils.sol";

/**
 * @title RecurringCollector contract
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCA (Recurring Collection Agreement).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is EIP712, GraphDirectory, Authorizable, IRecurringCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the RecurringCollectionAgreement struct
    bytes32 public constant EIP712_RCA_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreement(bytes16 agreementId,uint256 deadline,uint256 endsAt,address payer,address dataService,address serviceProvider,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
        );

    /// @notice The EIP712 typehash for the RecurringCollectionAgreementUpgrade struct
    bytes32 public constant EIP712_RCAU_TYPEHASH =
        keccak256(
            "RecurringCollectionAgreementUpgrade(bytes16 agreementId,uint256 deadline,uint256 endsAt,uint256 maxInitialTokens,uint256 maxOngoingTokensPerSecond,uint32 minSecondsPerCollection,uint32 maxSecondsPerCollection,bytes metadata)"
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
     * @notice Initiate a payment collection through the payments protocol.
     * See {IGraphPayments.collect}.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes calldata data) external returns (uint256) {
        require(
            paymentType == IGraphPayments.PaymentTypes.IndexingFee,
            RecurringCollectorInvalidPaymentType(paymentType)
        );
        try this.decodeCollectData(data) returns (CollectParams memory collectParams) {
            return _collect(collectParams);
        } catch {
            revert RecurringCollectorInvalidCollectData(data);
        }
    }

    /**
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
            RecurringCollectorAgreementDeadlineElapsed(signedRCA.rca.deadline)
        );

        // check that the voucher is signed by the payer (or proxy)
        _requireAuthorizedRCASigner(signedRCA);

        AgreementData storage agreement = _getForUpdateAgreement(signedRCA.rca.agreementId);
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
        _requireValidAgreement(agreement);

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
     * @notice Cancel an indexing agreement.
     * See {IRecurringCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(bytes16 agreementId, CancelAgreementBy by) external {
        AgreementData storage agreement = _getForUpdateAgreement(agreementId);
        require(
            agreement.state == AgreementState.Accepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );
        require(
            agreement.dataService == msg.sender,
            RecurringCollectorDataServiceNotAuthorized(agreementId, msg.sender)
        );
        agreement.canceledAt = uint64(block.timestamp);
        agreement.state = by == CancelAgreementBy.Payer
            ? AgreementState.CanceledByPayer
            : AgreementState.CanceledByServiceProvider;

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
     * @notice Upgrade an indexing agreement.
     * See {IRecurringCollector.upgrade}.
     * @dev Caller must be the data service for the agreement.
     */
    function upgrade(SignedRCAU calldata signedRCAU) external {
        require(
            signedRCAU.rcau.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(signedRCAU.rcau.deadline)
        );

        AgreementData storage agreement = _getForUpdateAgreement(signedRCAU.rcau.agreementId);
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

        // upgrade the agreement
        agreement.endsAt = signedRCAU.rcau.endsAt;
        agreement.maxInitialTokens = signedRCAU.rcau.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = signedRCAU.rcau.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = signedRCAU.rcau.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = signedRCAU.rcau.maxSecondsPerCollection;
        _requireValidAgreement(agreement);

        emit AgreementUpgraded(
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

    /**
     * @notice See {IRecurringCollector.recoverRCASigner}
     */
    function recoverRCASigner(SignedRCA calldata signedRCA) external view returns (address) {
        return _recoverRCASigner(signedRCA);
    }

    /**
     * @notice See {IRecurringCollector.recoverRCAUSigner}
     */
    function recoverRCAUSigner(SignedRCAU calldata signedRCAU) external view returns (address) {
        return _recoverRCAUSigner(signedRCAU);
    }

    /**
     * @notice See {IRecurringCollector.encodeRCA}
     */
    function encodeRCA(RecurringCollectionAgreement calldata rca) external view returns (bytes32) {
        return _encodeRCA(rca);
    }

    /**
     * @notice See {IRecurringCollector.encodeRCAU}
     */
    function encodeRCAU(RecurringCollectionAgreementUpgrade calldata rcau) external view returns (bytes32) {
        return _encodeRCAU(rcau);
    }

    /**
     * @notice See {IRecurringCollector.getAgreement}
     */
    function getAgreement(bytes16 agreementId) external view returns (AgreementData memory) {
        return _getAgreement(agreementId);
    }

    /**
     * @notice Decodes the collect data.
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
     * @param _params The decoded parameters for the collection
     * @return The amount of tokens collected
     */
    function _collect(CollectParams memory _params) private returns (uint256) {
        AgreementData storage agreement = _getForUpdateAgreement(_params.agreementId);
        require(
            agreement.state == AgreementState.Accepted || agreement.state == AgreementState.CanceledByPayer,
            RecurringCollectorAgreementIncorrectState(_params.agreementId, agreement.state)
        );

        require(
            msg.sender == agreement.dataService,
            RecurringCollectorDataServiceNotAuthorized(_params.agreementId, msg.sender)
        );

        require(
            agreement.endsAt >= block.timestamp,
            RecurringCollectorAgreementElapsed(_params.agreementId, agreement.endsAt)
        );

        uint256 tokensToCollect = 0;
        if (_params.tokens != 0) {
            tokensToCollect = _requireValidCollect(agreement, _params.agreementId, _params.tokens);

            _graphPaymentsEscrow().collect(
                IGraphPayments.PaymentTypes.IndexingFee,
                agreement.payer,
                agreement.serviceProvider,
                tokensToCollect,
                agreement.dataService,
                _params.dataServiceCut
            );
        }
        agreement.lastCollectionAt = uint64(block.timestamp);

        emit PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
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

    function _requireValidAgreement(AgreementData memory _agreement) private view {
        require(
            _agreement.dataService != address(0) &&
                _agreement.payer != address(0) &&
                _agreement.serviceProvider != address(0),
            RecurringCollectorAgreementInvalidParameters("zero address")
        );

        // Agreement needs to end in the future
        require(
            _agreement.endsAt > block.timestamp,
            RecurringCollectorAgreementInvalidParameters("endsAt not in future")
        );

        // Collection window needs to be at least 2 hours
        require(
            _agreement.maxSecondsPerCollection > _agreement.minSecondsPerCollection &&
                (_agreement.maxSecondsPerCollection - _agreement.minSecondsPerCollection >= 7200),
            RecurringCollectorAgreementInvalidParameters("too small collection window")
        );

        // Agreement needs to last at least one min collection window
        require(
            _agreement.endsAt - block.timestamp >= _agreement.minSecondsPerCollection + 7200,
            RecurringCollectorAgreementInvalidParameters("too small agreement window")
        );
    }

    /**
     * @notice Requires that the collection params are valid.
     */
    function _requireValidCollect(
        AgreementData memory _agreement,
        bytes16 _agreementId,
        uint256 _tokens
    ) private view returns (uint256) {
        uint256 collectionSeconds = _agreement.state == AgreementState.CanceledByPayer
            ? _agreement.canceledAt
            : block.timestamp;
        collectionSeconds -= _agreementCollectionStartAt(_agreement);
        require(
            collectionSeconds >= _agreement.minSecondsPerCollection,
            RecurringCollectorCollectionTooSoon(
                _agreementId,
                uint32(collectionSeconds),
                _agreement.minSecondsPerCollection
            )
        );
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

        return MathUtils.min(_tokens, maxTokens);
    }

    /**
     * @notice See {IRecurringCollector.recoverRCASigner}
     */
    function _recoverRCASigner(SignedRCA memory _signedRCA) private view returns (address) {
        bytes32 messageHash = _encodeRCA(_signedRCA.rca);
        return ECDSA.recover(messageHash, _signedRCA.signature);
    }

    /**
     * @notice See {IRecurringCollector.recoverRCAUSigner}
     */
    function _recoverRCAUSigner(SignedRCAU memory _signedRCAU) private view returns (address) {
        bytes32 messageHash = _encodeRCAU(_signedRCAU.rcau);
        return ECDSA.recover(messageHash, _signedRCAU.signature);
    }

    /**
     * @notice See {IRecurringCollector.encodeRCA}
     */
    function _encodeRCA(RecurringCollectionAgreement memory _rca) private view returns (bytes32) {
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
     * @notice See {IRecurringCollector.encodeRCAU}
     */
    function _encodeRCAU(RecurringCollectionAgreementUpgrade memory _rcau) private view returns (bytes32) {
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
     */
    function _requireAuthorizedRCASigner(SignedRCA memory _signedRCA) private view returns (address) {
        address signer = _recoverRCASigner(_signedRCA);
        require(_isAuthorized(_signedRCA.rca.payer, signer), RecurringCollectorInvalidSigner());

        return signer;
    }

    /**
     * @notice Requires that the signer for the RCAU is authorized
     * by the payer.
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
     */
    function _getForUpdateAgreement(bytes16 _agreementId) private view returns (AgreementData storage) {
        return agreements[_agreementId];
    }

    /**
     * @notice See {IRecurringCollector.getAgreement}
     */
    function _getAgreement(bytes16 _agreementId) private view returns (AgreementData memory) {
        return agreements[_agreementId];
    }

    function _agreementCollectionStartAt(AgreementData memory _agreement) private pure returns (uint256) {
        return _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;
    }
}
