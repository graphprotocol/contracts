// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IAuthorizable } from "../interfaces/IAuthorizable.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Authorizable is IAuthorizable {
    /// @notice The duration (in seconds) for which an authorization is thawing before it can be revoked
    uint256 public immutable REVOKE_AUTHORIZATION_THAWING_PERIOD;

    /// @notice Authorization details for authorizer-signer pairs
    mapping(address signer => Authorization authorization) private authorizations;

    /**
     * @notice Constructs a new instance of the Authorizable contract.
     * @param _revokeAuthorizationThawingPeriod The duration (in seconds) for which an authorization is thawing before it can be revoked.
     */
    constructor(uint256 _revokeAuthorizationThawingPeriod) {
        REVOKE_AUTHORIZATION_THAWING_PERIOD = _revokeAuthorizationThawingPeriod;
    }

    /**
     * @dev Revert if the caller has not authorized the signer
     */
    modifier onlyAuthorized(address _signer) {
        require(_isAuthorized(msg.sender, _signer), SignerNotAuthorized(msg.sender, _signer));
        _;
    }

    /**
     * See {IAuthorizable.authorizeSigner}.
     */
    function authorizeSigner(address _signer, uint256 _proofDeadline, bytes calldata _proof) external {
        require(
            authorizations[_signer].authorizer == address(0),
            SignerAlreadyAuthorized(authorizations[_signer].authorizer, _signer, authorizations[_signer].revoked)
        );
        _verifyAuthorizationProof(_proof, _proofDeadline, _signer);
        authorizations[_signer].authorizer = msg.sender;
        emit SignerAuthorized(msg.sender, _signer);
    }

    /**
     * See {IAuthorizable.thawSigner}.
     */
    function thawSigner(address _signer) external onlyAuthorized(_signer) {
        authorizations[_signer].thawEndTimestamp = block.timestamp + REVOKE_AUTHORIZATION_THAWING_PERIOD;
        emit SignerThawing(msg.sender, _signer, authorizations[_signer].thawEndTimestamp);
    }

    /**
     * See {IAuthorizable.cancelThawSigner}.
     */
    function cancelThawSigner(address _signer) external onlyAuthorized(_signer) {
        require(authorizations[_signer].thawEndTimestamp > 0, SignerNotThawing(_signer));
        authorizations[_signer].thawEndTimestamp = 0;
        emit SignerThawCanceled(msg.sender, _signer, 0);
    }

    /**
     * See {IAuthorizable.revokeAuthorizedSigner}.
     */
    function revokeAuthorizedSigner(address _signer) external onlyAuthorized(_signer) {
        uint256 thawEndTimestamp = authorizations[_signer].thawEndTimestamp;
        require(thawEndTimestamp > 0, SignerNotThawing(_signer));
        require(thawEndTimestamp <= block.timestamp, SignerStillThawing(block.timestamp, thawEndTimestamp));
        authorizations[_signer].revoked = true;
        emit SignerRevoked(msg.sender, _signer);
    }

    /**
     * See {IAuthorizable.getRevokeAuthorizationThawingPeriod}.
     */
    function getRevokeAuthorizationThawingPeriod() external view returns (uint256) {
        return REVOKE_AUTHORIZATION_THAWING_PERIOD;
    }

    /**
     * See {IAuthorizable.isAuthorized}.
     */
    function isAuthorized(address _authorizer, address _signer) external view returns (bool) {
        return _isAuthorized(_authorizer, _signer);
    }

    function _isAuthorized(address _authorizer, address _signer) internal view returns (bool) {
        return (authorizations[_signer].authorizer == _authorizer && !authorizations[_signer].revoked);
    }

    /**
     * @notice Verify the authorization proof provided by the authorizer
     * @param _proof The proof provided by the authorizer
     * @param _proofDeadline The deadline by which the proof must be verified
     * @param _signer The authorization recipient
     */
    function _verifyAuthorizationProof(bytes calldata _proof, uint256 _proofDeadline, address _signer) private view {
        // Check that the proofDeadline has not passed
        require(_proofDeadline > block.timestamp, InvalidSignerProofDeadline(_proofDeadline, block.timestamp));

        // Generate the message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(block.chainid, address(this), "authorizeSignerProof", _proofDeadline, msg.sender)
        );

        // Generate the allegedly signed digest
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // Verify that the recovered signer matches the to be authorized signer
        require(ECDSA.recover(digest, _proof) == _signer, InvalidSignerProof());
    }
}
