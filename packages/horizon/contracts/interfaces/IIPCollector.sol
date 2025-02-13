// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";
import { IGraphPayments } from "./IGraphPayments.sol";
import { IAuthorizable } from "./IAuthorizable.sol";

/**
 * @title Interface for the {IPCollector} contract
 * @dev Implements the {IPaymentCollector} interface as defined by the Graph
 * Horizon payments protocol.
 * @notice Implements a payments collector contract that can be used to collect
 * indexing agreement payments.
 */
interface IIPCollector is IAuthorizable, IPaymentsCollector {
    /// @notice A struct representing a signed IAV
    struct SignedIAV {
        // The IAV
        IndexingAgreementVoucher iav;
        // Signature - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
        bytes signature;
    }

    struct AgreementKey {
        address dataService;
        address payer;
        address serviceProvider;
        bytes16 agreementId;
    }

    struct CollectParams {
        AgreementKey key;
        bytes32 collectionId;
        uint256 tokens;
        uint256 dataServiceCut;
    }

    struct AgreementData {
        uint256 acceptedAt;
        uint256 lastCollection;
        uint256 duration;
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
    }

    /// @notice The Indexing Agreement Voucher (IAV) struct
    struct IndexingAgreementVoucher {
        // The agreement ID of the IAV
        bytes16 agreementId;
        // Accept params
        uint64 deadline;
        // The duration of the IAV in epochs
        uint256 duration;
        // The address of the payer the IAV was issued by
        address payer;
        // The address of the data service the IAV was issued to
        address dataService;
        // The address of the service provider the IAV was issued to
        address serviceProvider;
        // Collection params
        uint256 maxInitialTokens;
        uint256 maxOngoingTokensPerSecond;
        uint32 minSecondsPerCollection;
        uint32 maxSecondsPerCollection;
        // Arbitrary metadata to extend functionality if a data service requires it
        bytes metadata;
    }

    /**
     * @notice Emitted when an IAV is collected
     * @param payer The address of the payer
     * @param dataService The address of the data service
     * @param serviceProvider The address of the service provider
     * @param metadata Arbitrary metadata
     * @param signature The signature of the IAV
     */
    event IAVCollected(
        address indexed payer,
        address indexed dataService,
        address indexed serviceProvider,
        bytes metadata,
        bytes signature
    );

    /**
     * Thrown when the IAV signer is invalid
     */
    error IPCollectorInvalidIAVSigner();

    /**
     * Thrown when the proof deadline is invalid
     * @param proofDeadline The deadline for the proof provided
     * @param currentTimestamp The current timestamp
     */
    error IPCollectorInvalidProofDeadline(uint256 proofDeadline, uint256 currentTimestamp);

    /**
     * Thrown when the payment type is not IndexingFee
     * @param paymentType The provided payment type
     */
    error IPCollectorInvalidPaymentType(IGraphPayments.PaymentTypes paymentType);

    /**
     * Thrown when the caller is not the data service the IAV was issued to
     * @param caller The address of the caller
     * @param dataService The address of the data service
     */
    error IPCollectorCallerNotDataService(address caller, address dataService);

    /**
     * @dev Computes the hash of a IndexingAgreementVoucher (IAV).
     * @param iav The IAV for which to compute the hash.
     * @return The hash of the IAV.
     */
    function encodeIAV(IndexingAgreementVoucher calldata iav) external view returns (bytes32);

    /**
     * @dev Recovers the signer address of a signed IndexingAgreementVoucher (IAV).
     * @param signedIAV The SignedIAV containing the IAV and its signature.
     * @return The address of the signer.
     */
    function recoverIAVSigner(SignedIAV calldata signedIAV) external view returns (address);

    function accept(SignedIAV memory signedIAV) external;

    function cancel(address _payer, address _serviceProvider, bytes16 _agreementId) external;
}
