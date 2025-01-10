// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title Interface for the {Authorizable} contract
 * @notice Implements an authorization scheme that allows authorizers to
 * authorize signers to sign on their behalf.
 */
interface IAuthorizable {
    /**
     * @notice Details for an authorizer-signer pair
     * @dev Authorizations can be removed only after a thawing period
     */
    struct Authorization {
        // Resource owner
        address authorizer;
        // Timestamp at which thawing period ends (zero if not thawing)
        uint256 thawEndTimestamp;
        // Whether the signer authorization was revoked
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
     * @dev Emitted when the thawing of a signer is cancelled
     * @param authorizer The address of the authorizer cancelling the thawing
     * @param signer The address of the signer
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    event SignerThawCanceled(address indexed authorizer, address indexed signer, uint256 thawEndTimestamp);

    /**
     * @dev Emitted when a signer has been revoked
     * @param authorizer The address of the authorizer revoking the signer
     * @param signer The address of the signer
     */
    event SignerRevoked(address indexed authorizer, address indexed signer);

    /**
     * Thrown when the signer is already authorized
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     * @param revoked The revoked status of the authorization
     */
    error SignerAlreadyAuthorized(address authorizer, address signer, bool revoked);

    /**
     * Thrown when the attempting to modify a revoked signer
     * @param signer The address of the signer
     */
    error SignerAlreadyRevoked(address signer);

    /**
     * Thrown when the signer proof deadline is invalid
     * @param proofDeadline The deadline for the proof provided
     * @param currentTimestamp The current timestamp
     */
    error InvalidSignerProofDeadline(uint256 proofDeadline, uint256 currentTimestamp);

    /**
     * Thrown when the signer proof is invalid
     */
    error InvalidSignerProof();

    /**
     * Thrown when the signer is not authorized by the authorizer
     * @param authorizer The address of the authorizer
     * @param signer The address of the signer
     */
    error SignerNotAuthorized(address authorizer, address signer);

    /**
     * Thrown when the signer is not thawing
     * @param signer The address of the signer
     */
    error SignerNotThawing(address signer);

    /**
     * Thrown when the signer is still thawing
     * @param currentTimestamp The current timestamp
     * @param thawEndTimestamp The timestamp at which the thawing period ends
     */
    error SignerStillThawing(uint256 currentTimestamp, uint256 thawEndTimestamp);

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
     * @notice Returns the thawing period for revoking an authorization
     */
    function getRevokeAuthorizationThawingPeriod() external view returns (uint256);

    /**
     * @notice Returns true if the signer is authorized by the authorizer
     */
    function isAuthorized(address authorizer, address signer) external view returns (bool);
}
