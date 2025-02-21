// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { IGraphTallyCollector } from "../../interfaces/IGraphTallyCollector.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title GraphTallyCollector contract
 * @dev Implements the {IGraphTallyCollector}, {IPaymentCollector} and {IAuthorizable} interfaces.
 * @notice A payments collector contract that can be used to collect payments using a GraphTally RAV (Receipt Aggregate Voucher).
 * @dev Note that the contract expects the RAV aggregate value to be monotonically increasing, each successive RAV for the same
 * (data service-payer-receiver) tuple should have a value greater than the previous one. The contract will keep track of the tokens
 * already collected and calculate the difference to collect.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract GraphTallyCollector is EIP712, GraphDirectory, Authorizable, IGraphTallyCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the ReceiptAggregateVoucher struct
    bytes32 private constant EIP712_RAV_TYPEHASH =
        keccak256(
            "ReceiptAggregateVoucher(address payer,address serviceProvider,address dataService,uint64 timestampNs,uint128 valueAggregate,bytes metadata)"
        );

    /// @notice Tracks the amount of tokens already collected by a data service from a payer to a receiver.
    /// @dev The collectionId provides a secondary key for grouping payment tracking if needed. Data services that do not require
    /// grouping can use the same collectionId for all payments (0x00 or some other default value).
    mapping(address dataService => mapping(bytes32 collectionId => mapping(address receiver => mapping(address payer => uint256 tokens))))
        public tokensCollected;

    /**
     * @notice Constructs a new instance of the GraphTallyCollector contract.
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
     * @notice Initiate a payment collection through the payments protocol
     * See {IGraphPayments.collect}.
     * @dev Requirements:
     * - Caller must be the data service the RAV was issued to.
     * - Signer of the RAV must be authorized to sign for the payer.
     * - Service provider must have an active provision with the data service to collect payments.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes memory data) external override returns (uint256) {
        return _collect(paymentType, data, 0);
    }

    function collect(
        IGraphPayments.PaymentTypes paymentType,
        bytes memory data,
        uint256 tokensToCollect
    ) external override returns (uint256) {
        return _collect(paymentType, data, tokensToCollect);
    }

    /**
     * @notice See {IGraphTallyCollector.recoverRAVSigner}
     */
    function recoverRAVSigner(SignedRAV calldata signedRAV) external view override returns (address) {
        return _recoverRAVSigner(signedRAV);
    }

    /**
     * @notice See {IGraphTallyCollector.encodeRAV}
     */
    function encodeRAV(ReceiptAggregateVoucher calldata rav) external view returns (bytes32) {
        return _encodeRAV(rav);
    }

    /**
     * @notice See {IGraphTallyCollector.collect}
     */
    function _collect(
        IGraphPayments.PaymentTypes _paymentType,
        bytes memory _data,
        uint256 _tokensToCollect
    ) private returns (uint256) {
        (SignedRAV memory signedRAV, uint256 dataServiceCut) = abi.decode(_data, (SignedRAV, uint256));

        // Ensure caller is the RAV data service
        require(
            signedRAV.rav.dataService == msg.sender,
            GraphTallyCollectorCallerNotDataService(msg.sender, signedRAV.rav.dataService)
        );

        // Ensure RAV signer is authorized for the payer
        _requireAuthorizedSigner(signedRAV);

        bytes32 collectionId = signedRAV.rav.collectionId;
        address dataService = signedRAV.rav.dataService;
        address receiver = signedRAV.rav.serviceProvider;

        // Check the service provider has an active provision with the data service
        // This prevents an attack where the payer can deny the service provider from collecting payments
        // by using a signer as data service to syphon off the tokens in the escrow to an account they control
        {
            uint256 tokensAvailable = _graphStaking().getProviderTokensAvailable(
                signedRAV.rav.serviceProvider,
                signedRAV.rav.dataService
            );
            require(tokensAvailable > 0, GraphTallyCollectorUnauthorizedDataService(signedRAV.rav.dataService));
        }

        uint256 tokensToCollect = 0;
        address payer = signedRAV.rav.payer;
        {
            uint256 tokensRAV = signedRAV.rav.valueAggregate;
            uint256 tokensAlreadyCollected = tokensCollected[dataService][collectionId][receiver][payer];
            require(
                tokensRAV > tokensAlreadyCollected,
                GraphTallyCollectorInconsistentRAVTokens(tokensRAV, tokensAlreadyCollected)
            );

            if (_tokensToCollect == 0) {
                tokensToCollect = tokensRAV - tokensAlreadyCollected;
            } else {
                require(
                    _tokensToCollect <= tokensRAV - tokensAlreadyCollected,
                    GraphTallyCollectorInvalidTokensToCollectAmount(
                        _tokensToCollect,
                        tokensRAV - tokensAlreadyCollected
                    )
                );
                tokensToCollect = _tokensToCollect;
            }
        }

        if (tokensToCollect > 0) {
            tokensCollected[dataService][collectionId][receiver][payer] += tokensToCollect;
            _graphPaymentsEscrow().collect(_paymentType, payer, receiver, tokensToCollect, dataService, dataServiceCut);
        }

        emit PaymentCollected(_paymentType, collectionId, payer, receiver, dataService, tokensToCollect);

        // This event is emitted to allow reconstructing RAV history with onchain data.
        emit RAVCollected(
            collectionId,
            payer,
            receiver,
            dataService,
            signedRAV.rav.timestampNs,
            signedRAV.rav.valueAggregate,
            signedRAV.rav.metadata,
            signedRAV.signature
        );

        return tokensToCollect;
    }

    /**
     * @notice See {IGraphTallyCollector.recoverRAVSigner}
     */
    function _recoverRAVSigner(SignedRAV memory _signedRAV) private view returns (address) {
        bytes32 messageHash = _encodeRAV(_signedRAV.rav);
        return ECDSA.recover(messageHash, _signedRAV.signature);
    }

    /**
     * @notice See {IGraphTallyCollector.encodeRAV}
     */
    function _encodeRAV(ReceiptAggregateVoucher memory _rav) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RAV_TYPEHASH,
                        _rav.payer,
                        _rav.serviceProvider,
                        _rav.dataService,
                        _rav.timestampNs,
                        _rav.valueAggregate,
                        keccak256(_rav.metadata)
                    )
                )
            );
    }

    function _requireAuthorizedSigner(SignedRAV memory _signedRAV) private view {
        require(
            _isAuthorized(_signedRAV.rav.payer, _recoverRAVSigner(_signedRAV)),
            GraphTallyCollectorInvalidRAVSigner()
        );
    }
}
