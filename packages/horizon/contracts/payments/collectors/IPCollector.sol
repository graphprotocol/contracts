// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IIPCollector } from "../../interfaces/IIPCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title IPCollector contract
 * @dev Implements the {IIPCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using an IAV (Indexing Agreement Voucher).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract IPCollector is EIP712, GraphDirectory, Authorizable, IIPCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the IndexingAgreementVoucher struct
    bytes32 private constant EIP712_IAV_TYPEHASH =
        keccak256("IndexingAgreementVoucher(address dataService,address serviceProvider,bytes metadata)");

    /// @notice Tracks agreements
    mapping(address dataService => mapping(address payer => mapping(address serviceProvider => mapping(bytes16 agreementId => AgreementData data))))
        public agreements;

    uint256 constant CANCELED = type(uint256).max;

    /**
     * @notice Constructs a new instance of the IPCollector contract.
     * @param _eip712Name The name of the EIP712 domain.
     * @param _eip712Version The version of the EIP712 domain.
     * @param _controller The address of the Graph controller.
     * @param _revokeSignerThawingPeriod The duration (in seconds) in which a signer is thawing before they can be revoked.
     */
    constructor(
        string memory _eip712Name,
        string memory _eip712Version,
        address _controller,
        uint256 _revokeSignerThawingPeriod
    ) EIP712(_eip712Name, _eip712Version) GraphDirectory(_controller) Authorizable(_revokeSignerThawingPeriod) {}

    modifier onlyDataService(address _dataService) {
        require(_dataService == msg.sender, IPCollectorCallerNotDataService(msg.sender, _dataService));
        _;
    }

    /**
     * @notice Initiate a payment collection through the payments protocol.
     * See {IGraphPayments.collect}.
     * @dev Caller must be the data service the IAV was issued to.
     */
    function collect(IGraphPayments.PaymentTypes _paymentType, bytes calldata _data) external returns (uint256) {
        require(_paymentType == IGraphPayments.PaymentTypes.IndexingFee, IPCollectorInvalidPaymentType(_paymentType));
        try this.decodeCollectData(_data) returns (CollectParams memory _params) {
            return _collect(_params);
        } catch {
            revert("IPCollectorInvalidCollectData");
        }
    }

    function decodeCollectData(bytes calldata _data) public pure returns (CollectParams memory) {
        return abi.decode(_data, (CollectParams));
    }

    function _collect(CollectParams memory _params) private onlyDataService(_params.key.dataService) returns (uint256) {
        _requireValidCollect(_params.key, _params.tokens);

        _graphPaymentsEscrow().collect(
            IGraphPayments.PaymentTypes.IndexingFee,
            _params.key.payer,
            _params.key.serviceProvider,
            _params.tokens,
            _params.key.dataService,
            _params.dataServiceCut
        );

        emit PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
            _params.collectionId,
            _params.key.payer,
            _params.key.serviceProvider,
            _params.key.dataService,
            _params.tokens
        );
        return _params.tokens;
    }

    function _requireValidCollect(AgreementKey memory _key, uint256 _tokens) private {
        AgreementData storage agreement = _getForUpdateAgreement(_key);
        uint256 lastCollection = agreement.lastCollection;
        agreement.lastCollection = block.timestamp;

        require(agreement.acceptedAt > 0 && agreement.acceptedAt != CANCELED, "IPCollectorInvalidAgreementId");

        uint256 agreementEnd = agreement.duration < type(uint256).max - agreement.acceptedAt
            ? agreement.acceptedAt + agreement.duration
            : type(uint256).max;
        require(agreementEnd > block.timestamp, "IPCollectorAgreementElapsed");

        uint256 collectionSeconds = block.timestamp;
        collectionSeconds -= lastCollection > 0 ? lastCollection : agreement.acceptedAt;
        require(collectionSeconds >= agreement.minSecondsPerCollection, "IPCollectorCollectionTooSoon");
        require(collectionSeconds <= agreement.maxSecondsPerCollection, "IPCollectorCollectionTooLate");

        uint256 maxTokens = agreement.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += lastCollection == 0 ? agreement.maxInitialTokens : 0;

        require(_tokens <= maxTokens, "IPCollectorCollectionAmountTooHigh");
    }

    // Called from data service
    // Data service has to check the service provider
    // Collector checks the signer (a.k.a. the payer)
    function accept(SignedIAV memory signedIAV) external onlyDataService(signedIAV.iav.dataService) {
        // check that the voucher is signed by the payer (or proxy)
        _requireAuthorizedSigner(signedIAV);

        AgreementData storage agreement = _getForUpdateAgreement(
            AgreementKey({
                dataService: signedIAV.iav.dataService,
                payer: signedIAV.iav.payer,
                serviceProvider: signedIAV.iav.serviceProvider,
                agreementId: signedIAV.iav.agreementId
            })
        );
        // check that the agreement is not already accepted
        require(agreement.acceptedAt == 0, "IPCollectorInvalidAgreementId");

        // accept the agreement
        agreement.acceptedAt = block.timestamp;
        // these need to be validated to something that makes sense for the contract
        agreement.duration = signedIAV.iav.duration;
        agreement.maxInitialTokens = signedIAV.iav.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = signedIAV.iav.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = signedIAV.iav.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = signedIAV.iav.maxSecondsPerCollection;
    }

    // The caller owns their entire agreement namespace
    function cancel(address _payer, address _serviceProvider, bytes16 _agreementId) external {
        AgreementData storage agreement = _getForUpdateAgreement(
            AgreementKey({
                dataService: msg.sender,
                payer: _payer,
                serviceProvider: _serviceProvider,
                agreementId: _agreementId
            })
        );
        require(agreement.acceptedAt > 0, "IPCollectorInvalidAgreementId");
        agreement.acceptedAt = CANCELED;
    }

    /**
     * @notice See {IIPCollector.recoverIAVSigner}
     */
    function recoverIAVSigner(SignedIAV calldata _signedIAV) external view returns (address) {
        return _recoverIAVSigner(_signedIAV);
    }

    function _recoverIAVSigner(SignedIAV memory _signedIAV) private view returns (address) {
        bytes32 messageHash = _encodeIAV(_signedIAV.iav);
        return ECDSA.recover(messageHash, _signedIAV.signature);
    }

    /**
     * @notice See {IIPCollector.encodeIAV}
     */
    function encodeIAV(IndexingAgreementVoucher calldata _iav) external view returns (bytes32) {
        return _encodeIAV(_iav);
    }

    function _encodeIAV(IndexingAgreementVoucher memory _iav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(EIP712_IAV_TYPEHASH, _iav.dataService, _iav.serviceProvider, keccak256(_iav.metadata))
                )
            );
    }

    function _requireAuthorizedSigner(SignedIAV memory _signedIAV) private view returns (address) {
        address signer = _recoverIAVSigner(_signedIAV);
        require(_isAuthorized(_signedIAV.iav.payer, signer), IPCollectorInvalidIAVSigner());

        return signer;
    }

    function _getAgreement(AgreementKey memory _key) private view returns (AgreementData memory) {
        return agreements[_key.dataService][_key.payer][_key.serviceProvider][_key.agreementId];
    }

    function _getForUpdateAgreement(AgreementKey memory _key) private view returns (AgreementData storage) {
        return agreements[_key.dataService][_key.payer][_key.serviceProvider][_key.agreementId];
    }
}
