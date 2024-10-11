// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { ITAPCollector } from "../../interfaces/ITAPCollector.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title TAPCollector contract
 * @dev Implements the {ITAPCollector} and {IPaymentCollector} interfaces.
 * @notice A payments collector contract that can be used to collect payments using a TAP RAV (Receipt Aggregate Voucher).
 * @dev Note that the contract expects the RAV aggregate value to be monotonically increasing, each successive RAV for the same
 * (data service-payer-receiver) tuple should have a value greater than the previous one. The contract will keep track of the tokens
 * already collected and calculate the difference to collect.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract TAPCollector is EIP712, GraphDirectory, ITAPCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the ReceiptAggregateVoucher struct
    bytes32 private constant EIP712_RAV_TYPEHASH =
        keccak256(
            "ReceiptAggregateVoucher(address dataService,address serviceProvider,uint64 timestampNs,uint128 valueAggregate,bytes metadata)"
        );

    /// @notice Authorization details for payer-signer pairs
    mapping(address signer => PayerAuthorization authorizedSigner) public authorizedSigners;

    /// @notice Tracks the amount of tokens already collected by a data service from a payer to a receiver
    mapping(address dataService => mapping(address receiver => mapping(address payer => uint256 tokens)))
        public tokensCollected;

    /// @notice The duration (in seconds) in which a signer is thawing before they can be revoked
    uint256 public immutable REVOKE_SIGNER_THAWING_PERIOD;

    /**
     * @notice Constructs a new instance of the TAPVerifier contract.
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
    ) EIP712(eip712Name, eip712Version) GraphDirectory(controller) {
        REVOKE_SIGNER_THAWING_PERIOD = revokeSignerThawingPeriod;
    }

    /**
     * See {ITAPCollector.authorizeSigner}.
     */
    function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external override {
        require(
            authorizedSigners[signer].payer == address(0),
            TAPCollectorSignerAlreadyAuthorized(authorizedSigners[signer].payer, signer)
        );

        _verifyAuthorizedSignerProof(proof, proofDeadline, signer);

        authorizedSigners[signer].payer = msg.sender;
        authorizedSigners[signer].thawEndTimestamp = 0;
        emit SignerAuthorized(msg.sender, signer);
    }

    /**
     * See {ITAPCollector.thawSigner}.
     */
    function thawSigner(address signer) external override {
        PayerAuthorization storage authorization = authorizedSigners[signer];

        require(authorization.payer == msg.sender, TAPCollectorSignerNotAuthorizedByPayer(msg.sender, signer));

        authorization.thawEndTimestamp = block.timestamp + REVOKE_SIGNER_THAWING_PERIOD;
        emit SignerThawing(msg.sender, signer, authorization.thawEndTimestamp);
    }

    /**
     * See {ITAPCollector.cancelThawSigner}.
     */
    function cancelThawSigner(address signer) external override {
        PayerAuthorization storage authorization = authorizedSigners[signer];

        require(authorization.payer == msg.sender, TAPCollectorSignerNotAuthorizedByPayer(msg.sender, signer));
        require(authorization.thawEndTimestamp > 0, TAPCollectorSignerNotThawing(signer));

        authorization.thawEndTimestamp = 0;
        emit SignerThawCanceled(msg.sender, signer, 0);
    }

    /**
     * See {ITAPCollector.revokeAuthorizedSigner}.
     */
    function revokeAuthorizedSigner(address signer) external override {
        PayerAuthorization storage authorization = authorizedSigners[signer];

        require(authorization.payer == msg.sender, TAPCollectorSignerNotAuthorizedByPayer(msg.sender, signer));
        require(authorization.thawEndTimestamp > 0, TAPCollectorSignerNotThawing(signer));
        require(
            authorization.thawEndTimestamp <= block.timestamp,
            TAPCollectorSignerStillThawing(block.timestamp, authorization.thawEndTimestamp)
        );

        delete authorizedSigners[signer];
        emit SignerRevoked(msg.sender, signer);
    }

    /**
     * @notice Initiate a payment collection through the payments protocol
     * See {IGraphPayments.collect}.
     * @dev Caller must be the data service the RAV was issued to.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes memory data) external override returns (uint256) {
        (SignedRAV memory signedRAV, uint256 dataServiceCut) = abi.decode(data, (SignedRAV, uint256));
        require(
            signedRAV.rav.dataService == msg.sender,
            TAPCollectorCallerNotDataService(msg.sender, signedRAV.rav.dataService)
        );

        address signer = _recoverRAVSigner(signedRAV);
        require(authorizedSigners[signer].payer != address(0), TAPCollectorInvalidRAVSigner());

        return _collect(paymentType, authorizedSigners[signer].payer, signedRAV, dataServiceCut);
    }

    /**
     * @notice See {ITAPCollector.recoverRAVSigner}
     */
    function recoverRAVSigner(SignedRAV calldata signedRAV) external view override returns (address) {
        return _recoverRAVSigner(signedRAV);
    }

    /**
     * @notice See {ITAPCollector.encodeRAV}
     */
    function encodeRAV(ReceiptAggregateVoucher calldata rav) external view returns (bytes32) {
        return _encodeRAV(rav);
    }

    /**
     * @notice See {ITAPCollector.collect}
     */
    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        address _payer,
        SignedRAV memory _signedRAV,
        uint256 _dataServiceCut
    ) private returns (uint256) {
        address dataService = _signedRAV.rav.dataService;
        address receiver = _signedRAV.rav.serviceProvider;

        uint256 tokensRAV = _signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[dataService][receiver][_payer];
        require(
            tokensRAV > tokensAlreadyCollected,
            TAPCollectorInconsistentRAVTokens(tokensRAV, tokensAlreadyCollected)
        );

        uint256 tokensToCollect = tokensRAV - tokensAlreadyCollected;
        uint256 tokensDataService = tokensToCollect.mulPPM(_dataServiceCut);

        if (tokensToCollect > 0) {
            tokensCollected[dataService][receiver][_payer] = tokensRAV;
            _graphPaymentsEscrow().collect(
                _paymentType,
                _payer,
                receiver,
                tokensToCollect,
                dataService,
                tokensDataService
            );
        }

        emit PaymentCollected(_paymentType, _payer, receiver, tokensToCollect, dataService, tokensDataService);
        emit RAVCollected(
            _payer,
            dataService,
            receiver,
            _signedRAV.rav.timestampNs,
            _signedRAV.rav.valueAggregate,
            _signedRAV.rav.metadata,
            _signedRAV.signature
        );
        return tokensToCollect;
    }

    /**
     * @notice See {ITAPCollector.recoverRAVSigner}
     */
    function _recoverRAVSigner(SignedRAV memory _signedRAV) private view returns (address) {
        bytes32 messageHash = _encodeRAV(_signedRAV.rav);
        return ECDSA.recover(messageHash, _signedRAV.signature);
    }

    /**
     * @notice See {ITAPCollector.encodeRAV}
     */
    function _encodeRAV(ReceiptAggregateVoucher memory _rav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RAV_TYPEHASH,
                        _rav.dataService,
                        _rav.serviceProvider,
                        _rav.timestampNs,
                        _rav.valueAggregate,
                        keccak256(_rav.metadata)
                    )
                )
            );
    }

    /**
     * @notice Verify the proof provided by the payer authorizing the signer
     * @param _proof The proof provided by the payer authorizing the signer
     * @param _proofDeadline The deadline by which the proof must be verified
     * @param _signer The signer to be authorized
     */
    function _verifyAuthorizedSignerProof(bytes calldata _proof, uint256 _proofDeadline, address _signer) private view {
        // Verify that the proofDeadline has not passed
        require(
            _proofDeadline > block.timestamp,
            TAPCollectorInvalidSignerProofDeadline(_proofDeadline, block.timestamp)
        );

        // Generate the hash of the payer's address
        bytes32 messageHash = keccak256(abi.encodePacked(block.chainid, _proofDeadline, msg.sender));

        // Generate the digest to be signed by the signer
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify that the recovered signer matches the expected signer
        require(ECDSA.recover(digest, _proof) == _signer, TAPCollectorInvalidSignerProof());
    }
}
