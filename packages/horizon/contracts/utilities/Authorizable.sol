// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IAuthorizable } from "../interfaces/IAuthorizable.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Authorizable contract
 * @dev Implements the {IAuthorizable} interface.
 * @notice A mechanism to authorize signers to sign messages on behalf of an authorizer.
 * Signers cannot be reused for different authorizers.
 * @dev Contract uses "authorizeSignerProof" as the domain for signer proofs.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract Authorizable is IAuthorizable {
    /// @notice The duration (in seconds) for which an authorization is thawing before it can be revoked
    uint256 public immutable REVOKE_AUTHORIZATION_THAWING_PERIOD;

    /// @notice Authorization details for authorizer-signer pairs
    mapping(address signer => Authorization authorization) public authorizations;

    /**
     * @dev Revert if the caller has not authorized the signer
     */
    modifier onlyAuthorized(address signer) {
        _requireAuthorized(msg.sender, signer);
        _;
    }

    /**
     * @notice Constructs a new instance of the Authorizable contract.
     * @param revokeAuthorizationThawingPeriod The duration (in seconds) for which an authorization is thawing before it can be revoked.
     */
    constructor(uint256 revokeAuthorizationThawingPeriod) {
        REVOKE_AUTHORIZATION_THAWING_PERIOD = revokeAuthorizationThawingPeriod;
    }

    /**
     * See {IAuthorizable.authorizeSigner}.
     */
    function authorizeSigner(address signer, uint256 proofDeadline, bytes calldata proof) external {
        require(
            authorizations[signer].authorizer == address(0),
            AuthorizableSignerAlreadyAuthorized(
                authorizations[signer].authorizer,
                signer,
                authorizations[signer].revoked
            )
        );
        _verifyAuthorizationProof(proof, proofDeadline, signer);
        authorizations[signer].authorizer = msg.sender;
        emit SignerAuthorized(msg.sender, signer);
    }

    /**
     * See {IAuthorizable.thawSigner}.
     */
    function thawSigner(address signer) external onlyAuthorized(signer) {
        authorizations[signer].thawEndTimestamp = block.timestamp + REVOKE_AUTHORIZATION_THAWING_PERIOD;
        emit SignerThawing(msg.sender, signer, authorizations[signer].thawEndTimestamp);
    }

    /**
     * See {IAuthorizable.cancelThawSigner}.
     */
    function cancelThawSigner(address signer) external onlyAuthorized(signer) {
        require(authorizations[signer].thawEndTimestamp > 0, AuthorizableSignerNotThawing(signer));
        uint256 thawEnd = authorizations[signer].thawEndTimestamp;
        authorizations[signer].thawEndTimestamp = 0;
        emit SignerThawCanceled(msg.sender, signer, thawEnd);
    }

    /**
     * See {IAuthorizable.revokeAuthorizedSigner}.
     */
    function revokeAuthorizedSigner(address signer) external onlyAuthorized(signer) {
        uint256 thawEndTimestamp = authorizations[signer].thawEndTimestamp;
        require(thawEndTimestamp > 0, AuthorizableSignerNotThawing(signer));
        require(thawEndTimestamp <= block.timestamp, AuthorizableSignerStillThawing(block.timestamp, thawEndTimestamp));
        authorizations[signer].revoked = true;
        emit SignerRevoked(msg.sender, signer);
    }

    /**
     * See {IAuthorizable.getThawEnd}.
     */
    function getThawEnd(address signer) external view returns (uint256) {
        return authorizations[signer].thawEndTimestamp;
    }

    /**
     * See {IAuthorizable.isAuthorized}.
     */
    function isAuthorized(address authorizer, address signer) external view returns (bool) {
        return _isAuthorized(authorizer, signer);
    }

    /**
     * See {IAuthorizable.isAuthorized}.
     */
    function _isAuthorized(address _authorizer, address _signer) internal view returns (bool) {
        return (_authorizer != address(0) &&
            authorizations[_signer].authorizer == _authorizer &&
            !authorizations[_signer].revoked);
    }

    /**
     * @notice Reverts if the authorizer has not authorized the signer
     * @param _authorizer The address of the authorizer
     * @param _signer The address of the signer
     */
    function _requireAuthorized(address _authorizer, address _signer) internal view {
        require(_isAuthorized(_authorizer, _signer), AuthorizableSignerNotAuthorized(_authorizer, _signer));
    }

    /**
     * @notice Verify the authorization proof provided by the authorizer
     * @param _proof The proof provided by the authorizer
     * @param _proofDeadline The deadline by which the proof must be verified
     * @param _signer The authorization recipient
     */
    function _verifyAuthorizationProof(bytes calldata _proof, uint256 _proofDeadline, address _signer) private view {
        // Check that the proofDeadline has not passed
        require(
            _proofDeadline > block.timestamp,
            AuthorizableInvalidSignerProofDeadline(_proofDeadline, block.timestamp)
        );

        // Generate the message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(block.chainid, address(this), "authorizeSignerProof", _proofDeadline, msg.sender)
        );

        // Generate the allegedly signed digest
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify that the recovered signer matches the to be authorized signer
        require(ECDSA.recover(digest, _proof) == _signer, AuthorizableInvalidSignerProof());
    }
}
