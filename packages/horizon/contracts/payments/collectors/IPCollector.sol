// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IIPCollector } from "../../interfaces/IIPCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

    /// @notice Sentinel value to indicate an agreement has been canceled
    uint256 private constant CANCELED = type(uint256).max;

    /// @notice Tracks agreements
    mapping(address dataService => mapping(address payer => mapping(address serviceProvider => mapping(bytes16 agreementId => AgreementData data))))
        public agreements;

    /**
     * @notice Checks that msg sender is the data service
     * @param dataService The address of the dataService
     */
    modifier onlyDataService(address dataService) {
        require(dataService == msg.sender, IPCollectorCallerNotDataService(msg.sender, dataService));
        _;
    }

    /**
     * @notice Constructs a new instance of the IPCollector contract.
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
     * @dev Caller must be the data service the IAV was issued to.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes calldata data) external returns (uint256) {
        require(paymentType == IGraphPayments.PaymentTypes.IndexingFee, IPCollectorInvalidPaymentType(paymentType));
        try this.decodeCollectData(data) returns (CollectParams memory params) {
            return _collect(params);
        } catch {
            revert("IPCollectorInvalidCollectData");
        }
    }

    /**
     * @notice Accept an indexing agreement.
     * See {IIPCollector.accept}.
     * @dev Caller must be the data service the IAV was issued to.
     */
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

    /**
     * @notice Cancel an indexing agreement.
     * See {IIPCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(address payer, address serviceProvider, bytes16 agreementId) external {
        AgreementData storage agreement = _getForUpdateAgreement(
            AgreementKey({
                dataService: msg.sender,
                payer: payer,
                serviceProvider: serviceProvider,
                agreementId: agreementId
            })
        );
        require(agreement.acceptedAt > 0, "IPCollectorInvalidAgreementId");
        agreement.acceptedAt = CANCELED;
    }

    /**
     * @notice See {IIPCollector.recoverIAVSigner}
     */
    function recoverIAVSigner(SignedIAV calldata signedIAV) external view returns (address) {
        return _recoverIAVSigner(signedIAV);
    }

    /**
     * @notice See {IIPCollector.encodeIAV}
     */
    function encodeIAV(IndexingAgreementVoucher calldata iav) external view returns (bytes32) {
        return _encodeIAV(iav);
    }

    /**
     * @notice Decodes the collect data.
     */
    function decodeCollectData(bytes calldata data) public pure returns (CollectParams memory) {
        return abi.decode(data, (CollectParams));
    }

    /**
     * @notice Collect payment through the payments protocol.
     * @dev Caller must be the data service the IAV was issued to.
     */
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

    /**
     * @notice Validated that a collection is valid for the agreement.
     */
    function _requireValidCollect(AgreementKey memory _key, uint256 _tokens) private {
        AgreementData storage agreement = _getForUpdateAgreement(_key);
        uint256 lastCollection = agreement.lastCollection;
        agreement.lastCollection = block.timestamp;

        require(agreement.acceptedAt > 0 && agreement.acceptedAt != CANCELED, "IPCollectorInvalidAgreementId");

        uint256 agreementEnd = agreement.duration < type(uint256).max - agreement.acceptedAt
            ? agreement.acceptedAt + agreement.duration
            : type(uint256).max;
        require(agreementEnd >= block.timestamp, "IPCollectorAgreementElapsed");

        uint256 collectionSeconds = block.timestamp;
        collectionSeconds -= lastCollection > 0 ? lastCollection : agreement.acceptedAt;
        require(collectionSeconds >= agreement.minSecondsPerCollection, "IPCollectorCollectionTooSoon");
        require(collectionSeconds <= agreement.maxSecondsPerCollection, "IPCollectorCollectionTooLate");

        uint256 maxTokens = agreement.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += lastCollection == 0 ? agreement.maxInitialTokens : 0;

        require(_tokens <= maxTokens, "IPCollectorCollectAmountTooHigh");
    }

    /**
     * @notice See {IIPCollector.recoverIAVSigner}
     */
    function _recoverIAVSigner(SignedIAV memory _signedIAV) private view returns (address) {
        bytes32 messageHash = _encodeIAV(_signedIAV.iav);
        return ECDSA.recover(messageHash, _signedIAV.signature);
    }

    /**
     * @notice See {IIPCollector.encodeIAV}
     */
    function _encodeIAV(IndexingAgreementVoucher memory _iav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(EIP712_IAV_TYPEHASH, _iav.dataService, _iav.serviceProvider, keccak256(_iav.metadata))
                )
            );
    }

    /**
     * @notice Requires that the signer for the IAV is authorized
     * by the payer of the IAV.
     */
    function _requireAuthorizedSigner(SignedIAV memory _signedIAV) private view returns (address) {
        address signer = _recoverIAVSigner(_signedIAV);
        require(_isAuthorized(_signedIAV.iav.payer, signer), IPCollectorInvalidIAVSigner());

        return signer;
    }

    /**
     * @notice Gets an agreement.
     */
    function _getAgreement(AgreementKey memory _key) private view returns (AgreementData memory) {
        return agreements[_key.dataService][_key.payer][_key.serviceProvider][_key.agreementId];
    }

    /**
     * @notice Gets an agreement to be updated.
     */
    function _getForUpdateAgreement(AgreementKey memory _key) private view returns (AgreementData storage) {
        return agreements[_key.dataService][_key.payer][_key.serviceProvider][_key.agreementId];
    }
}
