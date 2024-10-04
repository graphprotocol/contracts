// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";

/**
 * @title Interface for the {TAPCollector} contract
 * @dev Implements the {IPaymentCollector} interface as defined by the Graph
 * Horizon payments protocol.
 * @notice Implements a payments collector contract that can be used to collect
 * payments using a TAP RAV (Receipt Aggregate Voucher).
 */
interface ITAPCollector is IPaymentsCollector {
    /// @notice The Receipt Aggregate Voucher (RAV) struct
    struct ReceiptAggregateVoucher {
        // The address of the data service the RAV was issued to
        address dataService;
        // The address of the service provider the RAV was issued to
        address serviceProvider;
        // The RAV timestamp, indicating the latest TAP Receipt in the RAV
        uint64 timestampNs;
        // Total amount owed to the service provider since the beginning of the
        // payer-service provider relationship, including all debt that is already paid for.
        uint128 valueAggregate;
        // Arbitrary metadata to extend functionality if a data service requires it
        bytes metadata;
    }

    /// @notice A struct representing a signed RAV
    struct SignedRAV {
        // The RAV
        ReceiptAggregateVoucher rav;
        // Signature - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
        bytes signature;
    }

    /**
     * @notice Emitted when a RAV is collected
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param timestampNs The timestamp of the RAV
     * @param valueAggregate The total amount owed to the service provider
     * @param metadata Arbitrary metadata
     * @param signature The signature of the RAV
     */
    event RAVCollected(
        address indexed payer,
        address indexed dataService,
        address indexed serviceProvider,
        uint64 timestampNs,
        uint128 valueAggregate,
        bytes metadata,
        bytes signature
    );

    /**
     * Thrown when the caller is not the data service the RAV was issued to
     * @param caller The address of the caller
     * @param dataService The address of the data service
     */
    error TAPCollectorCallerNotDataService(address caller, address dataService);

    /**
     * @notice Thrown when the tokens collected are inconsistent with the collection history
     * Each RAV should have a value greater than the previous one
     * @param tokens The amount of tokens in the RAV
     * @param tokensCollected The amount of tokens already collected
     */
    error TAPCollectorInconsistentRAVTokens(uint256 tokens, uint256 tokensCollected);

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
