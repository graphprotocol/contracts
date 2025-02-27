// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";
import { IGraphPayments } from "./IGraphPayments.sol";

/**
 * @title Interface for the {GraphTallyCollector} contract
 * @dev Implements the {IPaymentCollector} interface as defined by the Graph
 * Horizon payments protocol.
 * @notice Implements a payments collector contract that can be used to collect
 * payments using a GraphTally RAV (Receipt Aggregate Voucher).
 */
interface IGraphTallyCollector is IPaymentsCollector {
    /**
     * @notice The Receipt Aggregate Voucher (RAV) struct
     * @param collectionId The ID of the collection "bucket" the RAV belongs to. Note that multiple RAVs can be collected for the same collection id.
     * @param payer The address of the payer the RAV was issued by
     * @param serviceProvider The address of the service provider the RAV was issued to
     * @param dataService The address of the data service the RAV was issued to
     * @param timestampNs The RAV timestamp, indicating the latest GraphTally Receipt in the RAV
     * @param valueAggregate The total amount owed to the service provider since the beginning of the payer-service provider relationship, including all debt that is already paid for.
     * @param metadata Arbitrary metadata to extend functionality if a data service requires it
     */
    struct ReceiptAggregateVoucher {
        bytes32 collectionId;
        address payer;
        address serviceProvider;
        address dataService;
        uint64 timestampNs;
        uint128 valueAggregate;
        bytes metadata;
    }

    /**
     * @notice A struct representing a signed RAV
     * @param rav The RAV
     * @param signature The signature of the RAV - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
     */
    struct SignedRAV {
        ReceiptAggregateVoucher rav;
        bytes signature;
    }

    /**
     * @notice Emitted when a RAV is collected
     * @param collectionId The ID of the collection "bucket" the RAV belongs to.
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param timestampNs The timestamp of the RAV
     * @param valueAggregate The total amount owed to the service provider
     * @param metadata Arbitrary metadata
     * @param signature The signature of the RAV
     */
    event RAVCollected(
        bytes32 indexed collectionId,
        address indexed payer,
        address serviceProvider,
        address indexed dataService,
        uint64 timestampNs,
        uint128 valueAggregate,
        bytes metadata,
        bytes signature
    );

    /**
     * @notice Thrown when the RAV signer is invalid
     */
    error GraphTallyCollectorInvalidRAVSigner();

    /**
     * @notice Thrown when the RAV is for a data service the service provider has no provision for
     * @param dataService The address of the data service
     */
    error GraphTallyCollectorUnauthorizedDataService(address dataService);

    /**
     * @notice Thrown when the caller is not the data service the RAV was issued to
     * @param caller The address of the caller
     * @param dataService The address of the data service
     */
    error GraphTallyCollectorCallerNotDataService(address caller, address dataService);

    /**
     * @notice Thrown when the tokens collected are inconsistent with the collection history
     * Each RAV should have a value greater than the previous one
     * @param tokens The amount of tokens in the RAV
     * @param tokensCollected The amount of tokens already collected
     */
    error GraphTallyCollectorInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);

    /**
     * @notice Thrown when the attempting to collect more tokens than what it's owed
     * @param tokensToCollect The amount of tokens to collect
     * @param maxTokensToCollect The maximum amount of tokens to collect
     */
    error GraphTallyCollectorInvalidTokensToCollectAmount(uint256 tokensToCollect, uint256 maxTokensToCollect);

    /**
     * @notice See {IPaymentsCollector.collect}
     * This variant adds the ability to partially collect a RAV by specifying the amount of tokens to collect.
     *
     * Requirements:
     * - The amount of tokens to collect must be less than or equal to the total amount of tokens in the RAV minus
     *   the tokens already collected.
     * @param paymentType The payment type to collect
     * @param data Additional data required for the payment collection
     * @param tokensToCollect The amount of tokens to collect
     * @return The amount of tokens collected
     */
    function collect(
        IGraphPayments.PaymentTypes paymentType,
        bytes calldata data,
        uint256 tokensToCollect
    ) external returns (uint256);

    /**
     * @dev Recovers the signer address of a signed ReceiptAggregateVoucher (RAV).
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     */
    function recoverRAVSigner(SignedRAV calldata signedRAV) external view returns (address);

    /**
     * @dev Computes the hash of a ReceiptAggregateVoucher (RAV).
     * @param rav The RAV for which to compute the hash.
     * @return The hash of the RAV.
     */
    function encodeRAV(ReceiptAggregateVoucher calldata rav) external view returns (bytes32);
}
