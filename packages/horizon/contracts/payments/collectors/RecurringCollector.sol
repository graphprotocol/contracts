// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
// solhint-disable-next-line no-unused-import
import { IPaymentsCollector } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsCollector.sol"; // for @inheritdoc
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
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

    /// @notice Maximum gas forwarded to payer contract callbacks (beforeCollection / afterCollection).
    /// Caps gas available to payer implementations, preventing 63/64-rule gas siphoning attacks
    /// that could starve the core collect() call of gas.
    uint256 private constant MAX_PAYER_CALLBACK_GAS = 1_500_000;

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

    /**
     * @inheritdoc IRecurringCollector
     * @notice Accept a Recurring Collection Agreement.
     * @dev Caller must be the data service the RCA was issued to.
     */
    function accept(RecurringCollectionAgreement calldata rca, bytes calldata signature) external returns (bytes16) {
        /* solhint-disable gas-strict-inequalities */
        require(
            rca.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rca.deadline)
        );
        /* solhint-enable gas-strict-inequalities */

        AuthorizationBasis authBasis = 0 < signature.length
            ? AuthorizationBasis.Signature
            : AuthorizationBasis.ContractApproval;

        if (authBasis == AuthorizationBasis.ContractApproval)
            require(0 < rca.payer.code.length, RecurringCollectorApproverNotContract(rca.payer));

        _requireAuthorization(rca.payer, _hashRCA(rca), signature, authBasis);
        return _validateAndStoreAgreement(rca, authBasis);
    }

    /**
     * @notice Validates RCA fields and stores the agreement.
     * @param _rca The Recurring Collection Agreement to validate and store
     * @return agreementId The deterministically generated agreement ID
     */
    /* solhint-disable function-max-lines */
    function _validateAndStoreAgreement(
        RecurringCollectionAgreement memory _rca,
        AuthorizationBasis _authBasis
    ) private returns (bytes16) {
        bytes16 agreementId = _generateAgreementId(
            _rca.payer,
            _rca.dataService,
            _rca.serviceProvider,
            _rca.deadline,
            _rca.nonce
        );

        require(agreementId != bytes16(0), RecurringCollectorAgreementIdZero());
        require(msg.sender == _rca.dataService, RecurringCollectorUnauthorizedCaller(msg.sender, _rca.dataService));

        require(
            _rca.dataService != address(0) && _rca.payer != address(0) && _rca.serviceProvider != address(0),
            RecurringCollectorAgreementAddressNotSet()
        );

        _requireValidCollectionWindowParams(_rca.endsAt, _rca.minSecondsPerCollection, _rca.maxSecondsPerCollection);

        AgreementData storage agreement = _getAgreementStorage(agreementId);
        // check that the agreement is not already accepted
        require(
            agreement.state == AgreementState.NotAccepted,
            RecurringCollectorAgreementIncorrectState(agreementId, agreement.state)
        );

        // accept the agreement
        agreement.acceptedAt = uint64(block.timestamp);
        agreement.state = AgreementState.Accepted;
        agreement.dataService = _rca.dataService;
        agreement.payer = _rca.payer;
        agreement.serviceProvider = _rca.serviceProvider;
        agreement.endsAt = _rca.endsAt;
        agreement.maxInitialTokens = _rca.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = _rca.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = _rca.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = _rca.maxSecondsPerCollection;
        agreement.updateNonce = 0;
        agreement.authBasis = _authBasis;

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
            agreement.maxSecondsPerCollection,
            _authBasis
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

    /**
     * @inheritdoc IRecurringCollector
     * @notice Update a Recurring Collection Agreement.
     * @dev Caller must be the data service for the agreement.
     * @dev Note: Updated pricing terms apply immediately and will affect the next collection
     * for the entire period since lastCollectionAt.
     */
    function update(RecurringCollectionAgreementUpdate calldata rcau, bytes calldata signature) external {
        AgreementData storage agreement = _requireValidUpdateTarget(rcau.agreementId);

        /* solhint-disable gas-strict-inequalities */
        require(
            rcau.deadline >= block.timestamp,
            RecurringCollectorAgreementDeadlineElapsed(block.timestamp, rcau.deadline)
        );
        /* solhint-enable gas-strict-inequalities */

        AuthorizationBasis updateBasis = 0 < signature.length
            ? AuthorizationBasis.Signature
            : AuthorizationBasis.ContractApproval;
        require(
            updateBasis == agreement.authBasis,
            RecurringCollectorAuthorizationBasisMismatch(rcau.agreementId, agreement.authBasis, updateBasis)
        );

        _requireAuthorization(agreement.payer, _hashRCAU(rcau), signature, updateBasis);

        _validateAndStoreUpdate(agreement, rcau);
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
        AgreementData calldata agreement
    ) external view returns (bool isCollectable, uint256 collectionSeconds, AgreementNotCollectableReason reason) {
        return _getCollectionInfo(agreement);
    }

    /// @inheritdoc IRecurringCollector
    function getMaxNextClaim(bytes16 agreementId) external view returns (uint256) {
        return _getMaxNextClaim(agreements[agreementId]);
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
            /* solhint-disable gas-strict-inequalities */
            require(
                slippage <= _params.maxSlippage,
                RecurringCollectorExcessiveSlippage(_params.tokens, tokensToCollect, _params.maxSlippage)
            );
            /* solhint-enable gas-strict-inequalities */
        }
        agreement.lastCollectionAt = uint64(block.timestamp);

        // Hard eligibility gate and callbacks for contract-approved payers only.
        // Uses authBasis recorded at acceptance time rather than runtime code.length
        // to prevent EOAs from blocking collection via EIP-7702 delegation.
        // Low-level staticcall avoids caller-side ABI decoding reverts.
        if (0 < tokensToCollect && agreement.authBasis == AuthorizationBasis.ContractApproval) {
            // Gas guard: two external calls (staticcall + beforeCollection) each capped at
            // MAX_PAYER_CALLBACK_GAS. 64/63 accounts for EIP-150 63/64 gas forwarding rule.
            if (gasleft() < (2 * MAX_PAYER_CALLBACK_GAS * 64) / 63) {
                revert RecurringCollectorInsufficientCallbackGas();
            }
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory result) = agreement.payer.staticcall{ gas: MAX_PAYER_CALLBACK_GAS }(
                abi.encodeCall(IProviderEligibility.isEligible, (agreement.serviceProvider))
            );
            if (success && !(result.length < 32) && abi.decode(result, (uint256)) == 0) {
                revert RecurringCollectorCollectionNotEligible(_params.agreementId, agreement.serviceProvider);
            }
            // Let contract payers top up escrow if short
            try
                IAgreementOwner(agreement.payer).beforeCollection{ gas: MAX_PAYER_CALLBACK_GAS }(
                    _params.agreementId,
                    tokensToCollect
                )
            {} catch {}
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

        // Notify contract-approved payers so they can reconcile escrow in the same transaction.
        // Gas guard ensures the callback cannot be starved; try/catch still
        // absorbs non-gas failures so a buggy payer cannot block collection.
        if (agreement.authBasis == AuthorizationBasis.ContractApproval) {
            // 64/63 accounts for EIP-150 63/64 gas forwarding rule.
            if (gasleft() < (MAX_PAYER_CALLBACK_GAS * 64) / 63) {
                revert RecurringCollectorInsufficientCallbackGas();
            }
            try
                IAgreementOwner(agreement.payer).afterCollection{ gas: MAX_PAYER_CALLBACK_GAS }(
                    _params.agreementId,
                    tokensToCollect
                )
            {} catch {}
        }

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
     * @notice Verifies authorization for an EIP712 hash using the given basis.
     * @param _payer The payer address (signer owner for ECDSA, contract for approval)
     * @param _hash The EIP712 typed data hash
     * @param _signature The ECDSA signature (only used when basis is Signature)
     * @param _basis The authorization method to use
     */
    function _requireAuthorization(
        address _payer,
        bytes32 _hash,
        bytes memory _signature,
        AuthorizationBasis _basis
    ) private view {
        if (_basis == AuthorizationBasis.Signature) {
            address signer = ECDSA.recover(_hash, _signature);
            require(_isAuthorized(_payer, signer), RecurringCollectorInvalidSigner());
        } else {
            require(
                IAgreementOwner(_payer).approveAgreement(_hash) == IAgreementOwner.approveAgreement.selector,
                RecurringCollectorInvalidSigner()
            );
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
     * @notice Validates and stores an update to a Recurring Collection Agreement.
     * Shared validation/storage/emit logic for the update function.
     * @param _agreement The storage reference to the agreement data
     * @param _rcau The Recurring Collection Agreement Update to apply
     */
    function _validateAndStoreUpdate(
        AgreementData storage _agreement,
        RecurringCollectionAgreementUpdate calldata _rcau
    ) private {
        // validate nonce to prevent replay attacks
        uint32 expectedNonce = _agreement.updateNonce + 1;
        require(
            _rcau.nonce == expectedNonce,
            RecurringCollectorInvalidUpdateNonce(_rcau.agreementId, expectedNonce, _rcau.nonce)
        );

        _requireValidCollectionWindowParams(_rcau.endsAt, _rcau.minSecondsPerCollection, _rcau.maxSecondsPerCollection);

        // update the agreement
        _agreement.endsAt = _rcau.endsAt;
        _agreement.maxInitialTokens = _rcau.maxInitialTokens;
        _agreement.maxOngoingTokensPerSecond = _rcau.maxOngoingTokensPerSecond;
        _agreement.minSecondsPerCollection = _rcau.minSecondsPerCollection;
        _agreement.maxSecondsPerCollection = _rcau.maxSecondsPerCollection;
        _agreement.updateNonce = _rcau.nonce;

        emit AgreementUpdated(
            _agreement.dataService,
            _agreement.payer,
            _agreement.serviceProvider,
            _rcau.agreementId,
            uint64(block.timestamp),
            _agreement.endsAt,
            _agreement.maxInitialTokens,
            _agreement.maxOngoingTokensPerSecond,
            _agreement.minSecondsPerCollection,
            _agreement.maxSecondsPerCollection
        );
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
    function _agreementCollectionStartAt(AgreementData memory _agreement) private pure returns (uint256) {
        return _agreement.lastCollectionAt > 0 ? _agreement.lastCollectionAt : _agreement.acceptedAt;
    }

    /**
     * @notice Compute the maximum tokens collectable in the next collection (worst case).
     * @dev For active agreements uses endsAt as the collection end (worst case),
     * not block.timestamp (current). Returns 0 for non-collectable states.
     * @param _a The agreement data
     * @return The maximum tokens that could be collected
     */
    function _getMaxNextClaim(AgreementData memory _a) private pure returns (uint256) {
        // CanceledByServiceProvider = immediately non-collectable
        if (_a.state == AgreementState.CanceledByServiceProvider) return 0;
        // Only Accepted and CanceledByPayer are collectable
        if (_a.state != AgreementState.Accepted && _a.state != AgreementState.CanceledByPayer) return 0;

        // Collection starts from last collection (or acceptance if never collected)
        uint256 collectionStart = 0 < _a.lastCollectionAt ? _a.lastCollectionAt : _a.acceptedAt;

        // Determine the latest possible collection end
        uint256 collectionEnd;
        if (_a.state == AgreementState.CanceledByPayer) {
            // Payer cancel freezes the window at min(canceledAt, endsAt)
            collectionEnd = _a.canceledAt < _a.endsAt ? _a.canceledAt : _a.endsAt;
        } else {
            // Active: collection window capped at endsAt
            collectionEnd = _a.endsAt;
        }

        // No collection possible if window is empty
        // solhint-disable-next-line gas-strict-inequalities
        if (collectionEnd <= collectionStart) return 0;

        // Max seconds is capped by maxSecondsPerCollection (enforced by _requireValidCollect)
        uint256 windowSeconds = collectionEnd - collectionStart;
        uint256 maxSeconds = windowSeconds < _a.maxSecondsPerCollection ? windowSeconds : _a.maxSecondsPerCollection;

        uint256 maxClaim = _a.maxOngoingTokensPerSecond * maxSeconds;
        if (_a.lastCollectionAt == 0) maxClaim += _a.maxInitialTokens;
        return maxClaim;
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
