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
    /// @notice Details for a payer-signer pair
    /// @dev Signers can be removed only after a thawing period
    struct PayerAuthorization {
        // Payer the signer is authorized to sign for
        address payer;
        // Timestamp at which thawing period ends (zero if not thawing)
        uint256 thawEndTimestamp;
        // Whether the signer authorization was revoked
        bool revoked;
    }

    /// @notice The Receipt Aggregate Voucher (RAV) struct
    struct ReceiptAggregateVoucher {
        // The ID of the collection "bucket" the RAV belongs to. Note that multiple RAVs can be collected for the same collection id.
        bytes32 collectionId;
        // The address of the payer the RAV was issued by
        address payer;
        // The address of the service provider the RAV was issued to
        address serviceProvider;
        // The address of the data service the RAV was issued to
        address dataService;
        // The RAV timestamp, indicating the latest GraphTally Receipt in the RAV
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
     * @notice Emitted when a signer is authorized to sign RAVs for a payer
     * @param payer The address of the payer authorizing the signer
     * @param authorizedSigner The address of the authorized signer
     */
    event SignerAuthorized(address indexed payer, address indexed authorizedSigner);

    /**
     * @notice Emitted when a signer is thawed to be removed from the authorized signers list
     * @param payer The address of the payer thawing the signer
     * @param authorizedSigner The address of the signer to thaw
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event SignerThawing(address indexed payer, address indexed authorizedSigner, uint256 thawEndTimestamp);

    /**
     * @dev Emitted when the thawing of a signer is cancelled
     * @param payer The address of the payer cancelling the thawing
     * @param authorizedSigner The address of the authorized signer
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event SignerThawCanceled(address indexed payer, address indexed authorizedSigner, uint256 thawEndTimestamp);

    /**
     * @dev Emitted when a authorized signer has been revoked
     * @param payer The address of the payer revoking the signer
     * @param authorizedSigner The address of the authorized signer
     */
    event SignerRevoked(address indexed payer, address indexed authorizedSigner);

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
     * Thrown when the signer is already authorized
     * @param authorizingPayer The address of the payer authorizing the signer
     * @param signer The address of the signer
     */
    error GraphTallyCollectorSignerAlreadyAuthorized(address authorizingPayer, address signer);

    /**
     * Thrown when the signer proof deadline is invalid
     * @param proofDeadline The deadline for the proof provided by the signer
     * @param currentTimestamp The current timestamp
     */
    error GraphTallyCollectorInvalidSignerProofDeadline(uint256 proofDeadline, uint256 currentTimestamp);

    /**
     * Thrown when the signer proof is invalid
     */
    error GraphTallyCollectorInvalidSignerProof();

    /**
     * Thrown when the signer is not authorized by the payer
     * @param payer The address of the payer
     * @param signer The address of the signer
     */
    error GraphTallyCollectorSignerNotAuthorizedByPayer(address payer, address signer);

    /**
     * Thrown when the attempting to revoke a signer that was already revoked
     * @param signer The address of the signer
     */
    error GraphTallyCollectorAuthorizationAlreadyRevoked(address payer, address signer);

    /**
     * Thrown when attempting to thaw a signer that is already thawing
     * @param signer The address of the signer
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    error GraphTallyCollectorSignerAlreadyThawing(address signer, uint256 thawEndTimestamp);

    /**
     * Thrown when the signer is not thawing
     * @param signer The address of the signer
     */
    error GraphTallyCollectorSignerNotThawing(address signer);

    /**
     * Thrown when the signer is still thawing
     * @param currentTimestamp The current timestamp
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    error GraphTallyCollectorSignerStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);

    /**
     * Thrown when the RAV signer is invalid
     */
    error GraphTallyCollectorInvalidRAVSigner();

    /**
     * Thrown when the RAV payer does not match the signers authorized payer
     * @param authorizedPayer The address of the authorized payer
     * @param ravPayer The address of the RAV payer
     */
    error GraphTallyCollectorInvalidRAVPayer(address authorizedPayer, address ravPayer);

    /**
     * Thrown when the RAV is for a data service the service provider has no provision for
     * @param dataService The address of the data service
     */
    error GraphTallyCollectorUnauthorizedDataService(address dataService);

    /**
     * Thrown when the caller is not the data service the RAV was issued to
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
     * Thrown when the attempting to collect more tokens than what it's owed
     * @param tokensToCollect The amount of tokens to collect
     * @param maxTokensToCollect The maximum amount of tokens to collect
     */
    error GraphTallyCollectorInvalidTokensToCollectAmount(uint256 tokensToCollect, uint256 maxTokensToCollect);

    /**
     * @notice Authorize a signer to sign on behalf of the payer.
     * A signer can not be authorized for multiple payers even after revoking previous authorizations.
     * @dev Requirements:
     * - `signer` must not be already authorized
     * - `proofDeadline` must be greater than the current timestamp
     * - `proof` must be a valid signature from the signer being authorized
     *
     * Emits an {SignerAuthorized} event
     * @param signer The addres of the authorized signer
     * @param proofDeadline The deadline for the proof provided by the signer
     * @param proof The proof provided by the signer to be authorized by the payer, consists of (chainID, proof deadline, sender address)
     */
    function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external;

    /**
     * @notice Starts thawing a signer to be removed from the authorized signers list
     * @dev Thawing a signer alerts receivers that signatures from that signer will soon be deemed invalid.
     * Receivers without existing signed receipts or RAVs from this signer should treat them as unauthorized.
     * Those with existing signed documents from this signer should work towards settling their engagements.
     * Once a signer is thawed, they should be viewed as revoked regardless of their revocation status.
     * Requirements:
     * - `signer` must be authorized by the payer calling this function
     *
     * Emits a {SignerThawing} event
     * @param signer The address of the signer to thaw
     */
    function thawSigner(address signer) external;

    /**
     * @notice Stops thawing a signer.
     * @dev Requirements:
     * - `signer` must be thawing and authorized by the payer calling this function
     *
     * Emits a {SignerThawCanceled} event
     * @param signer The address of the signer to cancel thawing
     */
    function cancelThawSigner(address signer) external;

    /**
     * @notice Revokes a signer from the authorized signers list if thawed.
     * @dev Requirements:
     * - `signer` must be thawed and authorized by the payer calling this function
     *
     * Emits a {SignerRevoked} event
     * @param signer The address of the signer
     */
    function revokeAuthorizedSigner(address signer) external;

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
