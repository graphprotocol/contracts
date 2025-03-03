// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title Interface for the {Authorizable} contract
 * @notice Implements an authorization scheme that allows authorizers to
 * authorize signers to sign on their behalf.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IAuthorizable {
    /**
     * @notice Details for an authorizer-signer pair
     * @dev Authorizations can be removed only after a thawing period
     * @param authorizer The address of the authorizer - resource owner
     * @param thawEndTimestamp The timestamp at which the thawing period ends (zero if not thawing)
     * @param revoked Whether the signer authorization was revoked
     */
    struct Authorization {
        address authorizer;
        uint256 thawEndTimestamp;
        bool revoked;
    }

    /**
     * @notice Emitted when a signer is authorized to sign for a authorizer
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     */
    event SignerAuthorized(address indexed authorizer, address indexed signer);

    /**
     * @notice Emitted when a signer is thawed to be de-authorized
     * @param authorizer The address of the authorizer thawing the signer
     * @param signer The address of the signer to thaw
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event SignerThawing(address indexed authorizer, address indexed signer, uint256 thawEndTimestamp);

    /**
     * @notice Emitted when the thawing of a signer is cancelled
     * @param authorizer The address of the authorizer cancelling the thawing
     * @param signer The address of the signer
     * @param thawEndTimestamp The timestamp at which the thawing period was scheduled to end
     */
    event SignerThawCanceled(address indexed authorizer, address indexed signer, uint256 thawEndTimestamp);

    /**
     * @notice Emitted when a signer has been revoked after thawing
     * @param authorizer The address of the authorizer revoking the signer
     * @param signer The address of the signer
     */
    event SignerRevoked(address indexed authorizer, address indexed signer);

    /**
     * @notice Thrown when attempting to authorize a signer that is already authorized
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     * @param revoked The revoked status of the authorization
     */
    error AuthorizableSignerAlreadyAuthorized(address authorizer, address signer, bool revoked);

    /**
     * @notice Thrown when the signer proof deadline is invalid
     * @param proofDeadline The deadline for the proof provided
     * @param currentTimestamp The current timestamp
     */
    error AuthorizableInvalidSignerProofDeadline(uint256 proofDeadline, uint256 currentTimestamp);

    /**
     * @notice Thrown when the signer proof is invalid
     */
    error AuthorizableInvalidSignerProof();

    /**
     * @notice Thrown when the signer is not authorized by the authorizer
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     */
    error AuthorizableSignerNotAuthorized(address authorizer, address signer);

    /**
     * @notice Thrown when the signer is not thawing
     * @param signer The address of the signer
     */
    error AuthorizableSignerNotThawing(address signer);

    /**
     * @notice Thrown when the signer is still thawing
     * @param currentTimestamp The current timestamp
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    error AuthorizableSignerStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);

    /**
     * @notice Authorize a signer to sign on behalf of the authorizer
     * @dev Requirements:
     * - `signer` must not be already authorized
     * - `proofDeadline` must be greater than the current timestamp
     * - `proof` must be a valid signature from the signer being authorized
     *
     * Emits a {SignerAuthorized} event
     * @param signer The addres of the signer
     * @param proofDeadline The deadline for the proof provided by the signer
     * @param proof The proof provided by the signer to be authorized by the authorizer
     * consists of (chain id, verifying contract address, domain, proof deadline, authorizer address)
     */
    function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external;

    /**
     * @notice Starts thawing a signer to be de-authorized
     * @dev Thawing a signer signals that signatures from that signer will soon be deemed invalid.
     * Once a signer is thawed, they should be viewed as revoked regardless of their revocation status.
     * If a signer is already thawing and this function is called, the thawing period is reset.
     * Requirements:
     * - `signer` must be authorized by the authorizer calling this function
     *
     * Emits a {SignerThawing} event
     * @param signer The address of the signer to thaw
     */
    function thawSigner(address signer) external;

    /**
     * @notice Stops thawing a signer.
     * @dev Requirements:
     * - `signer` must be thawing and authorized by the function caller
     *
     * Emits a {SignerThawCanceled} event
     * @param signer The address of the signer to cancel thawing
     */
    function cancelThawSigner(address signer) external;

    /**
     * @notice Revokes a signer if thawed.
     * @dev Requirements:
     * - `signer` must be thawed and authorized by the function caller
     *
     * Emits a {SignerRevoked} event
     * @param signer The address of the signer
     */
    function revokeAuthorizedSigner(address signer) external;

    /**
     * @notice Returns the timestamp at which the thawing period ends for a signer
     * @param signer The address of the signer
     * @return The timestamp at which the thawing period ends
     */
    function getThawEnd(address signer) external view returns (uint256);

    /**
     * @notice Returns true if the signer is authorized by the authorizer
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     * @return true if the signer is authorized by the authorizer, false otherwise
     */
    function isAuthorized(address authorizer, address signer) external view returns (bool);
}
