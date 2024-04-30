// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { ITAPVerifier } from "./interfaces/ITAPVerifier.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title TAPVerifier
 * @dev A contract for verifying receipt aggregation vouchers.
 */
contract TAPVerifier is EIP712, ITAPVerifier {
    bytes32 private constant EIP712_RAV_TYPEHASH =
        keccak256(
            "ReceiptAggregateVoucher(address dataService, address serviceProvider,uint64 timestampNs,uint128 valueAggregate,bytes metadata)"
        );

    // The duration (in seconds) in which a signer is thawing before they can be revoked
    uint256 public immutable REVOKE_SIGNER_THAWING_PERIOD;

    // Map of signer to authorized signer information
    mapping(address signer => SenderAuthorization authorizedSigner) public authorizedSigners;

    /**
     * @dev Emitted when a signer is authorized to sign RAVs for a sender.
     */
    event AuthorizeSigner(address indexed signer, address indexed sender);
    /**
     * @dev Emitted when a thaw request is made for authorized signer
     */
    event ThawSigner(address indexed sender, address indexed authorizedSigner, uint256 thawEndTimestamp);

    /**
     * @dev Emitted when the thawing of a signer is cancelled
     */
    event CancelThawSigner(address indexed sender, address indexed authorizedSigner, uint256 thawEndTimestamp);

    /**
     * @dev Emitted when a authorized signer has been revoked
     */
    event RevokeAuthorizedSigner(address indexed sender, address indexed authorizedSigner);

    error TAPVerifierInvalidCaller(address sender, address expected);
    error TAPVerifierInvalidSignerProof();
    error TAPVerifierAlreadyAuthorized(address signer, address authorizingSender);
    error TAPVerifierNotAuthorized(address signer, address sender);
    error TAPVerifierNotThawing();
    error TAPVerifierStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);

    /**
     * @dev Constructs a new instance of the TAPVerifier contract.
     */
    constructor(string memory eip712Name, string memory eip712Version) EIP712(eip712Name, eip712Version) {}

    /**
     * @dev Authorizes a signer to sign RAVs for the sender.
     * @param signer Address of the authorized signer.
     * @param proof The proof provided by the signer to authorize the sender, consisting of packed (chainID, proof deadline, sender address).
     * @dev The proof deadline is the timestamp at which the proof expires. The proof is susceptible to replay attacks until the deadline is reached.
     * @notice REVERT with error:
     *               - SignerAlreadyAuthorized: Signer is currently authorized for a sender
     *               - InvalidSignerProof: The provided signer proof is invalid
     */
    function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external {
        if (authorizedSigners[signer].sender != address(0)) {
            revert TAPVerifierAlreadyAuthorized(signer, authorizedSigners[signer].sender);
        }

        _verifyAuthorizedSignerProof(proof, proofDeadline, signer);

        authorizedSigners[signer].sender = msg.sender;
        authorizedSigners[signer].thawEndTimestamp = 0;
        emit AuthorizeSigner(signer, msg.sender);
    }

    /**
     * @dev Starts thawing a signer to be removed from the authorized signers list.
     * @param signer Address of the signer to remove.
     * @notice WARNING: Thawing a signer alerts receivers that signatures from that signer will soon be deemed invalid.
     * Receivers without existing signed receipts or RAVs from this signer should treat them as unauthorized.
     * Those with existing signed documents from this signer should work towards settling their engagements.
     * Once a signer is thawed, they should be viewed as revoked regardless of their revocation status.
     * @notice REVERT with error:
     *               - SignerNotAuthorizedBySender: The provided signer is either not authorized or
     *                 authorized by a different sender
     */
    function thawSigner(address signer) external {
        SenderAuthorization storage authorization = authorizedSigners[signer];

        if (authorization.sender != msg.sender) {
            revert TAPVerifierNotAuthorized(signer, authorizedSigners[signer].sender);
        }

        authorization.thawEndTimestamp = block.timestamp + REVOKE_SIGNER_THAWING_PERIOD;
        emit ThawSigner(authorization.sender, signer, authorization.thawEndTimestamp);
    }

    /**
     * @dev Stops thawing a signer.
     * @param signer Address of the signer to stop thawing.
     * @notice REVERT with error:
     *               - SignerNotAuthorizedBySender: The provided signer is either not authorized or
     *                 authorized by a different sender
     */
    function cancelThawSigner(address signer) external {
        SenderAuthorization storage authorization = authorizedSigners[signer];

        if (authorization.sender != msg.sender) {
            revert TAPVerifierNotAuthorized(signer, authorizedSigners[signer].sender);
        }

        authorization.thawEndTimestamp = 0;
        emit CancelThawSigner(authorization.sender, signer, authorization.thawEndTimestamp);
    }

    /**
     * @dev Revokes a signer from the authorized signers list if thawed.
     * @param signer Address of the signer to remove.
     * @notice REVERT with error:
     *               - SignerNotAuthorizedBySender: The provided signer is either not authorized or
     *                 authorized by a different sender
     *               - SignerNotThawing: No thaw was initiated for the provided signer
     *               - SignerStillThawing: ThawEndTimestamp has not been reached
     *                 for provided signer
     */
    function revokeAuthorizedSigner(address signer) external {
        SenderAuthorization storage authorization = authorizedSigners[signer];

        if (authorization.sender != msg.sender) {
            revert TAPVerifierNotAuthorized(signer, authorizedSigners[signer].sender);
        }

        if (authorization.thawEndTimestamp == 0) {
            revert TAPVerifierNotThawing();
        }

        if (authorization.thawEndTimestamp > block.timestamp) {
            revert TAPVerifierStillThawing({
                currentTimestamp: block.timestamp,
                thawEndTimestamp: authorization.thawEndTimestamp
            });
        }

        delete authorizedSigners[signer];
        emit RevokeAuthorizedSigner(authorization.sender, signer);
    }

    /**
     * @notice Verify validity of a SignedRAV
     * @dev Caller must be the data service the RAV was issued to.
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function verify(SignedRAV calldata signedRAV) external view returns (address) {
        if (signedRAV.rav.dataService != msg.sender) {
            revert TAPVerifierInvalidCaller(msg.sender, signedRAV.rav.dataService);
        }
        return recover(signedRAV);
    }

    /**
     * @dev Recovers the signer address of a signed ReceiptAggregateVoucher (RAV).
     * @param signedRAV The SignedRAV containing the RAV and its signature.
     * @return The address of the signer.
     * @notice REVERT: This function may revert if ECDSA.recover fails, check ECDSA library for details.
     */
    function recover(SignedRAV calldata signedRAV) public view returns (address) {
        bytes32 messageHash = encodeRAV(signedRAV.rav);
        return ECDSA.recover(messageHash, signedRAV.signature);
    }

    /**
     * @dev Computes the hash of a ReceiptAggregateVoucher (RAV).
     * @param rav The RAV for which to compute the hash.
     * @return The hash of the RAV.
     */
    function encodeRAV(ReceiptAggregateVoucher calldata rav) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EIP712_RAV_TYPEHASH,
                        rav.dataService,
                        rav.serviceProvider,
                        rav.timestampNs,
                        rav.valueAggregate
                    )
                )
            );
    }

    /**
     * @dev Verifies a proof that authorizes the sender to authorize the signer.
     * @param _proof The proof provided by the signer to authorize the sender.
     * @param _signer The address of the signer being authorized.
     * @notice REVERT with error:
     *               - InvalidSignerProof: If the given proof is not valid
     */
    function _verifyAuthorizedSignerProof(bytes calldata _proof, uint256 _proofDeadline, address _signer) private view {
        // Verify that the proof deadline has not passed
        if (block.timestamp > _proofDeadline) {
            revert TAPVerifierInvalidSignerProof();
        }

        // Generate the hash of the sender's address
        bytes32 messageHash = keccak256(abi.encodePacked(block.chainid, _proofDeadline, msg.sender));

        // Generate the digest to be signed by the signer
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify that the recovered signer matches the expected signer
        if (ECDSA.recover(digest, _proof) != _signer) {
            revert TAPVerifierInvalidSignerProof();
        }
    }
}
