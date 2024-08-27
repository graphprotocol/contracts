// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { ITAPCollector } from "../../interfaces/ITAPCollector.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TAPCollector contract
 * @dev Implements the {ITAPCollector} and {IPaymentCollector} interfaces.
 * @notice A payments collector contract that can be used to collect payments using a TAP RAV (Receipt Aggregate Voucher).
 * @dev Note that the contract expects the RAV aggregate value to be monotonically increasing, each successive RAV for the same
 * (data service-payer-receiver) tuple should have a value greater than the previous one. The contract will keep track of the tokens
 * already collected and calculate the difference to collect.
 */
contract TAPCollector is EIP712, GraphDirectory, ITAPCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the ReceiptAggregateVoucher struct
    bytes32 private constant EIP712_RAV_TYPEHASH =
        keccak256(
            "ReceiptAggregateVoucher(address dataService,address serviceProvider,uint64 timestampNs,uint128 valueAggregate,bytes metadata)"
        );

    /// @notice Tracks the amount of tokens already collected by a data service from a payer to a receiver
    mapping(address dataService => mapping(address receiver => mapping(address payer => uint256 tokens)))
        public tokensCollected;

    /**
     * @notice Constructs a new instance of the TAPVerifier contract.
     * @param eip712Name The name of the EIP712 domain.
     * @param eip712Version The version of the EIP712 domain.
     * @param controller The address of the Graph controller.
     */
    constructor(
        string memory eip712Name,
        string memory eip712Version,
        address controller
    ) EIP712(eip712Name, eip712Version) GraphDirectory(controller) {}

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

        address dataService = signedRAV.rav.dataService;
        address payer = _recoverRAVSigner(signedRAV);
        address receiver = signedRAV.rav.serviceProvider;

        uint256 tokensRAV = signedRAV.rav.valueAggregate;
        uint256 tokensAlreadyCollected = tokensCollected[dataService][receiver][payer];
        require(
            tokensRAV > tokensAlreadyCollected,
            TAPCollectorInconsistentRAVTokens(tokensRAV, tokensAlreadyCollected)
        );

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

        emit PaymentCollected(paymentType, payer, receiver, tokensToCollect, dataService, tokensDataService);
        return tokensToCollect;
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
}
