// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { ITAPCollector } from "../../interfaces/ITAPCollector.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { GraphDirectory } from "../../data-service/GraphDirectory.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TAPVerifier
 * @dev A contract for verifying receipt aggregation vouchers.
 */
contract TAPCollector is EIP712, GraphDirectory, ITAPCollector {
    using PPMMath for uint256;

    bytes32 private constant EIP712_RAV_TYPEHASH =
        keccak256(
            "ReceiptAggregateVoucher(address dataService, address serviceProvider,uint64 timestampNs,uint128 valueAggregate,bytes metadata)"
        );

    mapping(address dataService => mapping(address receiver => mapping(address payer => uint256 tokens)))
        public tokensCollected;

    event TAPCollectorCollected(
        IGraphPayments.PaymentTypes indexed paymentType,
        address indexed payer,
        address receiver,
        uint256 tokensReceiver,
        address indexed dataService,
        uint256 tokensDataService
    );

    error TAPCollectorCallerNotDataService(address caller, address dataService);
    error TAPVerifierInvalidSignerProof();
    error TAPCollectorInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);

    /**
     * @dev Constructs a new instance of the TAPVerifier contract.
     */
    constructor(
        string memory eip712Name,
        string memory eip712Version,
        address controller
    ) EIP712(eip712Name, eip712Version) GraphDirectory(controller) {}

    /**
     * @notice Verify validity of a SignedRAV
     * @dev Caller must be the data service the RAV was issued to.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes memory data) external returns (uint256) {
        (SignedRAV memory signedRAV, uint256 dataServiceCut) = abi.decode(data, (SignedRAV, uint256));

        if (signedRAV.rav.dataService != msg.sender) {
            revert TAPCollectorCallerNotDataService(msg.sender, signedRAV.rav.dataService);
        }

        address dataService = signedRAV.rav.dataService;
        address payer = _recoverRAVSigner(signedRAV);
        address receiver = signedRAV.rav.serviceProvider;

        uint256 tokensRAV = signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[dataService][receiver][payer];
        if (tokensRAV < tokensAlreadyCollected) {
            revert TAPCollectorInconsistentRAVTokens(tokensRAV, tokensAlreadyCollected);
        }

        uint256 tokensToCollect = tokensRAV - tokensAlreadyCollected;
        uint256 tokensDataService = tokensToCollect.mulPPM(dataServiceCut);

        if (tokensToCollect > 0) {
            _graphPaymentsEscrow().collect(
                paymentType,
                payer,
                receiver,
                tokensToCollect,
                dataService,
                tokensDataService
            );
            tokensCollected[dataService][receiver][payer] = tokensRAV;
        }

        emit TAPCollectorCollected(paymentType, payer, receiver, tokensToCollect, dataService, tokensDataService);
        return tokensToCollect;
    }

    /**
     * @dev Recovers the signer address of a signed ReceiptAggregateVoucher (RAV).
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function recoverRAVSigner(SignedRAV calldata signedRAV) public view returns (address) {
        return _recoverRAVSigner(signedRAV);
    }

    /**
     * @dev Computes the hash of a ReceiptAggregateVoucher (RAV).
     * @param rav The RAV for which to compute the hash.
     * @return The hash of the RAV.
     */
    function encodeRAV(ReceiptAggregateVoucher calldata rav) public view returns (bytes32) {
        return _encodeRAV(rav);
    }

    function _recoverRAVSigner(SignedRAV memory _signedRAV) private view returns (address) {
        bytes32 messageHash = _encodeRAV(_signedRAV.rav);
        return ECDSA.recover(messageHash, _signedRAV.signature);
    }

    function _encodeRAV(ReceiptAggregateVoucher memory _rav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RAV_TYPEHASH,
                        _rav.dataService,
                        _rav.serviceProvider,
                        _rav.timestampNs,
                        _rav.valueAggregate
                    )
                )
            );
    }
}
