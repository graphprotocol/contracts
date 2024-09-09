// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { AttestationManagerV1Storage } from "./AttestationManagerStorage.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Attestation } from "../libraries/Attestation.sol";

/**
 * @title AttestationManager contract
 * @notice A helper contract implementing attestation verification.
 * Uses a custom implementation of EIP712 for backwards compatibility with attestations.
 */
abstract contract AttestationManager is Initializable, AttestationManagerV1Storage {
    /// @notice EIP712 type hash for Receipt struct
    bytes32 private constant RECEIPT_TYPE_HASH =
        keccak256("Receipt(bytes32 requestCID,bytes32 responseCID,bytes32 subgraphDeploymentID)");

    /// @notice EIP712 domain type hash
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /// @notice EIP712 domain name
    bytes32 private constant DOMAIN_NAME_HASH = keccak256("Graph Protocol");

    /// @notice EIP712 domain version
    bytes32 private constant DOMAIN_VERSION_HASH = keccak256("0");

    /// @notice EIP712 domain salt
    bytes32 private constant DOMAIN_SALT = 0xa070ffb1cd7409649bf77822cce74495468e06dbfaef09556838bf188679b9c2;

    /**
     * @dev Initialize the AttestationManager contract and parent contracts
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AttestationManager_init() internal onlyInitializing {
        __AttestationManager_init_unchained();
    }

    /**
     * @dev Initialize the AttestationManager contract
     */
    // solhint-disable-next-line func-name-mixedcase
    function __AttestationManager_init_unchained() internal onlyInitializing {
        _domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                DOMAIN_NAME_HASH,
                DOMAIN_VERSION_HASH,
                block.chainid,
                address(this),
                DOMAIN_SALT
            )
        );
    }

    /**
     * @dev Recover the signer address of the `_attestation`.
     * @param _attestation The attestation struct
     * @return Signer address
     */
    function _recoverSigner(Attestation.State memory _attestation) internal view returns (address) {
        // Obtain the hash of the fully-encoded message, per EIP-712 encoding
        Attestation.Receipt memory receipt = Attestation.Receipt(
            _attestation.requestCID,
            _attestation.responseCID,
            _attestation.subgraphDeploymentId
        );
        bytes32 messageHash = _encodeReceipt(receipt);

        // Obtain the signer of the fully-encoded EIP-712 message hash
        // NOTE: The signer of the attestation is the indexer that served the request
        return ECDSA.recover(messageHash, abi.encodePacked(_attestation.r, _attestation.s, _attestation.v));
    }

    /**
     * @dev Get the message hash that a indexer used to sign the receipt.
     * Encodes a receipt using a domain separator, as described on
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#specification.
     * @notice Return the message hash used to sign the receipt
     * @param _receipt Receipt returned by indexer and submitted by fisherman
     * @return Message hash used to sign the receipt
     */
    function _encodeReceipt(Attestation.Receipt memory _receipt) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // EIP-191 encoding pad, EIP-712 version 1
                    _domainSeparator,
                    keccak256(
                        abi.encode(
                            RECEIPT_TYPE_HASH,
                            _receipt.requestCID,
                            _receipt.responseCID,
                            _receipt.subgraphDeploymentId
                        ) // EIP 712-encoded message hash
                    )
                )
            );
    }
}
